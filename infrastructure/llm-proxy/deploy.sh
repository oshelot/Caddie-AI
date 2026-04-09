#!/bin/bash
# Deploy CaddieAI LLM Proxy — updates existing Lambda in-place
# Usage: ./deploy.sh [--profile caddieai]
#
# Installs dependencies, zips the package, updates Lambda code + config,
# adds the Lambda Web Adapter layer, and creates a Function URL with
# RESPONSE_STREAM invoke mode.
#
# Backend: Amazon Bedrock (Nova Micro) — no external API keys needed.

set -euo pipefail

FUNCTION_NAME="caddieai-llm-proxy"
REGION="us-east-2"
PROFILE_ARG=""
LAYER_ARN="arn:aws:lambda:us-east-2:753240598075:layer:LambdaAdapterLayerX86:27"
BEDROCK_MODEL_ID="us.amazon.nova-micro-v1:0"
EVAL_TABLE_NAME="caddieai-llm-eval"
PROXY_API_KEY="${PROXY_API_KEY:?Set PROXY_API_KEY env var before running deploy}"

# Shadow evaluation config (JSON string — edit to add/remove models)
SHADOW_MODELS='{"nova-lite":{"model_id":"us.amazon.nova-lite-v1:0","provider":"bedrock"}}'
SHADOW_SAMPLE_RATE="1.0"

# Parse --profile flag
for arg in "$@"; do
    case $arg in
        --profile)
            shift
            PROFILE_ARG="--profile $1"
            shift
            ;;
        --profile=*)
            PROFILE_ARG="--profile ${arg#*=}"
            shift
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
ZIP_FILE="$SCRIPT_DIR/llm-proxy-streaming.zip"

echo "==> Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Installing dependencies (targeting Linux x86_64)..."
python3 -m pip install \
    --platform manylinux2014_x86_64 \
    --implementation cp \
    --python-version 3.12 \
    --only-binary=:all: \
    -r "$SCRIPT_DIR/requirements.txt" \
    -t "$BUILD_DIR" \
    --quiet

echo "==> Copying application files..."
cp "$SCRIPT_DIR/app.py" "$BUILD_DIR/"
cp "$SCRIPT_DIR/shadow_eval.py" "$BUILD_DIR/"
cp "$SCRIPT_DIR/run.sh" "$BUILD_DIR/"
chmod +x "$BUILD_DIR/run.sh"

echo "==> Creating deployment package..."
cd "$BUILD_DIR"
zip -r "$ZIP_FILE" . -q
cd "$SCRIPT_DIR"

echo "==> Updating Lambda function code..."
aws lambda update-function-code \
    --function-name "$FUNCTION_NAME" \
    --zip-file "fileb://$ZIP_FILE" \
    --region "$REGION" \
    $PROFILE_ARG \
    --output text --query 'FunctionArn'

echo "==> Waiting for update to complete..."
aws lambda wait function-updated \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    $PROFILE_ARG

echo "==> Updating Lambda configuration (handler, layer, env vars)..."
# Build environment JSON (SHADOW_MODELS contains braces, so we use --cli-input-json style)
ENV_JSON=$(cat <<ENVEOF
{
  "Variables": {
    "AWS_LAMBDA_EXEC_WRAPPER": "/opt/bootstrap",
    "AWS_LWA_INVOKE_MODE": "response_stream",
    "PORT": "8000",
    "PROXY_API_KEY": "$PROXY_API_KEY",
    "BEDROCK_MODEL_ID": "$BEDROCK_MODEL_ID",
    "SHADOW_MODELS": $(echo "$SHADOW_MODELS" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))"),
    "SHADOW_SAMPLE_RATE": "$SHADOW_SAMPLE_RATE",
    "EVAL_TABLE_NAME": "$EVAL_TABLE_NAME"
  }
}
ENVEOF
)
aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --handler "run.sh" \
    --layers "$LAYER_ARN" \
    --environment "$ENV_JSON" \
    --timeout 90 \
    --memory-size 512 \
    --region "$REGION" \
    $PROFILE_ARG \
    --output text --query 'FunctionArn'

echo "==> Waiting for config update to complete..."
aws lambda wait function-updated \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    $PROFILE_ARG

echo "==> Creating Function URL with RESPONSE_STREAM..."
FUNCTION_URL=$(aws lambda create-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --auth-type NONE \
    --invoke-mode RESPONSE_STREAM \
    --cors '{"AllowOrigins":["*"],"AllowMethods":["POST"],"AllowHeaders":["Content-Type","x-api-key"]}' \
    --region "$REGION" \
    $PROFILE_ARG \
    --output text --query 'FunctionUrl' 2>/dev/null) || \
FUNCTION_URL=$(aws lambda get-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    $PROFILE_ARG \
    --output text --query 'FunctionUrl')

echo "==> Adding public invoke permission..."
aws lambda add-permission \
    --function-name "$FUNCTION_NAME" \
    --statement-id FunctionURLAllowPublicAccess \
    --action lambda:InvokeFunctionUrl \
    --principal "*" \
    --function-url-auth-type NONE \
    --region "$REGION" \
    $PROFILE_ARG 2>/dev/null || echo "    (permission already exists)"

echo "==> Ensuring DynamoDB eval table exists..."
aws dynamodb create-table \
    --table-name "$EVAL_TABLE_NAME" \
    --attribute-definitions \
        AttributeName=request_id,AttributeType=S \
        AttributeName=model_id,AttributeType=S \
        AttributeName=timestamp,AttributeType=S \
        AttributeName=role,AttributeType=S \
    --key-schema \
        AttributeName=request_id,KeyType=HASH \
        AttributeName=model_id,KeyType=RANGE \
    --global-secondary-indexes \
        'IndexName=model-timestamp-index,KeySchema=[{AttributeName=model_id,KeyType=HASH},{AttributeName=timestamp,KeyType=RANGE}],Projection={ProjectionType=ALL}' \
        'IndexName=role-timestamp-index,KeySchema=[{AttributeName=role,KeyType=HASH},{AttributeName=timestamp,KeyType=RANGE}],Projection={ProjectionType=ALL}' \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" \
    $PROFILE_ARG 2>/dev/null || echo "    (table already exists)"

aws dynamodb update-time-to-live \
    --table-name "$EVAL_TABLE_NAME" \
    --time-to-live-specification Enabled=true,AttributeName=ttl \
    --region "$REGION" \
    $PROFILE_ARG 2>/dev/null || echo "    (TTL already configured)"

echo ""
echo "==> Deploy complete!"
echo "    Function URL: $FUNCTION_URL"
echo "    Model: $BEDROCK_MODEL_ID"
echo "    Shadow models: $SHADOW_MODELS"
echo "    Shadow sample rate: $SHADOW_SAMPLE_RATE"
echo "    Eval table: $EVAL_TABLE_NAME"
echo ""
echo "    Test buffered:"
echo "    curl -X POST '$FUNCTION_URL' -H 'Content-Type: application/json' -H 'x-api-key: \$PROXY_API_KEY' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Say hello\"}]}'"
echo ""
echo "    Test streaming:"
echo "    curl -N -X POST '$FUNCTION_URL' -H 'Content-Type: application/json' -H 'x-api-key: \$PROXY_API_KEY' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Say hello\"}],\"stream\":true}'"

# Cleanup
rm -rf "$BUILD_DIR"
echo ""
echo "==> Cleaned up build artifacts."
