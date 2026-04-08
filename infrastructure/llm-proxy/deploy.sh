#!/bin/bash
# Deploy CaddieAI LLM Proxy — updates existing Lambda in-place
# Usage: ./deploy.sh [--profile caddieai]
#
# Installs dependencies, zips the package, updates Lambda code + config,
# adds the Lambda Web Adapter layer, and creates a Function URL with
# RESPONSE_STREAM invoke mode.

set -euo pipefail

FUNCTION_NAME="caddieai-llm-proxy"
REGION="us-east-2"
PROFILE_ARG=""
LAYER_ARN="arn:aws:lambda:us-east-2:753240598075:layer:LambdaAdapterLayerX86:27"

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
aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --handler "run.sh" \
    --layers "$LAYER_ARN" \
    --environment "Variables={AWS_LAMBDA_EXEC_WRAPPER=/opt/bootstrap,AWS_LWA_INVOKE_MODE=response_stream,PORT=8000,PROXY_API_KEY=Gfc1TMjXjjQqfmTcj5ipetDCUx8_a4Kl6owwZqjV99E,SECRET_ID=caddieai/openai-api-key}" \
    --timeout 60 \
    --memory-size 256 \
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

echo ""
echo "==> Deploy complete!"
echo "    Function URL: $FUNCTION_URL"
echo ""
echo "    Test buffered:"
echo "    curl -X POST '$FUNCTION_URL' -H 'Content-Type: application/json' -H 'x-api-key: Gfc1TMjXjjQqfmTcj5ipetDCUx8_a4Kl6owwZqjV99E' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Say hello\"}]}'"
echo ""
echo "    Test streaming:"
echo "    curl -N -X POST '$FUNCTION_URL' -H 'Content-Type: application/json' -H 'x-api-key: Gfc1TMjXjjQqfmTcj5ipetDCUx8_a4Kl6owwZqjV99E' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Say hello\"}],\"stream\":true}'"

# Cleanup
rm -rf "$BUILD_DIR"
echo ""
echo "==> Cleaned up build artifacts."
