# CaddieAI LLM Proxy — Deployment Guide

## Architecture

```
Mobile App  →  Lambda Function URL  →  Lambda (FastAPI + Web Adapter)  →  OpenAI API
                (RESPONSE_STREAM)         ↕ Secrets Manager
```

The proxy runs as a FastAPI app inside AWS Lambda using the
[Lambda Web Adapter](https://github.com/aws/aws-lambda-web-adapter) layer.
This enables true **response streaming** — SSE chunks from OpenAI are forwarded
incrementally to the client via Lambda Function URL's `RESPONSE_STREAM` invoke mode.

### Why Lambda Web Adapter?

Native Lambda response streaming only supports Node.js managed runtimes.
Lambda Web Adapter bridges this gap by running a standard HTTP server (FastAPI/uvicorn)
inside the Lambda container and proxying between the Lambda Runtime API and the app.
The ZIP-based layer approach avoids Docker images — deploy stays simple.

## Prerequisites

- AWS CLI v2 configured with credentials for account `736255088782`
- [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html) installed
- Python 3.12
- The OpenAI API key already stored in Secrets Manager at `caddieai/openai-api-key`

## Files

| File | Purpose |
|------|---------|
| `app.py` | FastAPI application — streaming & buffered handlers |
| `run.sh` | Bootstrap script that starts uvicorn on port 8000 |
| `requirements.txt` | Python dependencies (fastapi, uvicorn, httpx, boto3) |
| `template.yaml` | SAM template — Lambda, Function URL, IAM, layer |
| `lambda_function.py` | **Legacy** — original buffered-only handler (kept for reference) |

## Deploy with SAM

```bash
cd infrastructure/llm-proxy

# Build (installs dependencies into .aws-sam/)
sam build --use-container

# Deploy (first time — interactive, saves config to samconfig.toml)
sam deploy --guided \
  --stack-name caddieai-llm-proxy \
  --region us-east-2 \
  --parameter-overrides ProxyApiKey=<YOUR_PROXY_API_KEY>

# Subsequent deploys (uses saved config)
sam build --use-container && sam deploy
```

SAM will output the **Function URL** — this is the new endpoint for client apps.

## Manual Deploy (without SAM)

If you prefer not to use SAM:

### 1. Install dependencies locally

```bash
cd infrastructure/llm-proxy
pip install -r requirements.txt -t ./package
cp app.py run.sh ./package/
cd package && zip -r ../llm-proxy-streaming.zip . && cd ..
```

### 2. Create or update the Lambda function

```bash
# Create (first time)
aws lambda create-function \
  --function-name caddieai-llm-proxy \
  --runtime python3.12 \
  --handler run.sh \
  --role arn:aws:iam::736255088782:role/caddieai-llm-proxy-role \
  --zip-file fileb://llm-proxy-streaming.zip \
  --timeout 60 \
  --memory-size 256 \
  --layers arn:aws:lambda:us-east-2:753240598075:layer:LambdaAdapterLayerX86:27 \
  --environment "Variables={AWS_LAMBDA_EXEC_WRAPPER=/opt/bootstrap,AWS_LWA_INVOKE_MODE=response_stream,PORT=8000,PROXY_API_KEY=<KEY>,SECRET_ID=caddieai/openai-api-key}" \
  --region us-east-2

# Update code (subsequent deploys)
aws lambda update-function-code \
  --function-name caddieai-llm-proxy \
  --zip-file fileb://llm-proxy-streaming.zip \
  --region us-east-2
```

### 3. Create Function URL with streaming

```bash
aws lambda create-function-url-config \
  --function-name caddieai-llm-proxy \
  --auth-type NONE \
  --invoke-mode RESPONSE_STREAM \
  --cors '{"AllowOrigins":["*"],"AllowMethods":["POST"],"AllowHeaders":["Content-Type","x-api-key"]}' \
  --region us-east-2
```

### 4. Allow public invocation

```bash
aws lambda add-permission \
  --function-name caddieai-llm-proxy \
  --statement-id FunctionURLAllowPublicAccess \
  --action lambda:InvokeFunctionUrl \
  --principal "*" \
  --function-url-auth-type NONE \
  --region us-east-2
```

## Test

### Buffered (non-streaming)

```bash
FUNCTION_URL="https://<id>.lambda-url.us-east-2.on.aws/"

curl -X POST "$FUNCTION_URL" \
  -H "Content-Type: application/json" \
  -H "x-api-key: <YOUR_PROXY_API_KEY>" \
  -d '{
    "messages": [{"role": "user", "content": "Say hello in 5 words"}],
    "max_tokens": 50
  }'
```

### Streaming

```bash
curl -N -X POST "$FUNCTION_URL" \
  -H "Content-Type: application/json" \
  -H "x-api-key: <YOUR_PROXY_API_KEY>" \
  -d '{
    "messages": [{"role": "user", "content": "Explain golf handicaps briefly"}],
    "max_tokens": 200,
    "stream": true
  }'
```

Expected streaming output:
```
data: {"content": "A"}
data: {"content": " golf"}
data: {"content": " handicap"}
...
data: {"usage": {"prompt_tokens": 12, "completion_tokens": 45, "total_tokens": 57}}
data: [DONE]
```

## SSE Protocol (for client implementors)

| Event | Format | When |
|-------|--------|------|
| Content chunk | `data: {"content": "text"}\n\n` | Each token/word from OpenAI |
| Error | `data: {"error": "message"}\n\n` | On upstream error |
| Usage | `data: {"usage": {"prompt_tokens": N, ...}}\n\n` | After last content chunk |
| Done | `data: [DONE]\n\n` | Stream complete |

Clients should:
1. Open an `EventSource` or `URLSession` stream to the Function URL
2. Parse each `data:` line as JSON
3. Append `content` values to build the full response
4. Record `usage` for telemetry
5. Close on `[DONE]`

## Migration from API Gateway

The previous setup used API Gateway → Lambda (buffered). To migrate:

1. Deploy this stack (creates a new Function URL endpoint)
2. Update `Secrets.plist` (iOS) and `BuildConfig` (Android) with the new URL
3. Client code sends `"stream": true` to opt into streaming
4. Non-streaming requests (`"stream": false` or omitted) work identically to before
5. Once verified, decommission the old API Gateway endpoint

## Rollback

The original `lambda_function.py` is preserved. To rollback:

```bash
# Re-deploy with the original handler
zip lambda_function.zip lambda_function.py
aws lambda update-function-code \
  --function-name caddieai-llm-proxy \
  --zip-file fileb://lambda_function.zip \
  --region us-east-2

# Remove the Web Adapter layer and reset handler
aws lambda update-function-configuration \
  --function-name caddieai-llm-proxy \
  --handler lambda_function.lambda_handler \
  --layers [] \
  --environment "Variables={PROXY_API_KEY=<KEY>,SECRET_ID=caddieai/openai-api-key}" \
  --region us-east-2
```

## Cost

Lambda Function URLs have no additional cost beyond standard Lambda pricing.
Response streaming bandwidth: first 6 MB per invocation is uncapped, then 2 MB/s.
Typical LLM responses are well under 6 MB.
