# AWS API Gateway — Deep Dive Knowledge Base
> **Stack:** Node.js + Express → AWS Lambda + API Gateway (Serverless Framework)

---

## Table of Contents

1. [Why We Moved Away From EC2](#1-why-we-moved-away-from-ec2)
2. [What is AWS API Gateway?](#2-what-is-aws-api-gateway)
3. [API Gateway Types](#3-api-gateway-types)
4. [REST API — Deep Dive (The One We Use)](#4-rest-api--deep-dive)
   - [Resources](#41-resources)
   - [Methods](#42-methods)
   - [Integration Types](#43-integration-types)
   - [Lambda Proxy Integration](#44-lambda-proxy-integration--the-key-concept)
5. [How Lambda + API Gateway Work Together](#5-how-lambda--api-gateway-work-together)
6. [How We Configured It (Our Project)](#6-how-we-configured-it-our-project)
   - [The Problem with the Old server.js](#61-the-old-serverjs--ec2-style)
   - [The New lambda.js Entry Point](#62-the-new-lambdajs-entry-point)
   - [serverless.yml Explained Line by Line](#63-serverlessyml-explained-line-by-line)
   - [How Requests Flow](#64-how-requests-flow)
7. [The Proxy+ Pattern](#7-the-proxy-pattern--why-it-is-the-magic)
8. [serverless-http — The Glue Layer](#8-serverless-http--the-glue-layer)
9. [CORS in API Gateway](#9-cors-in-api-gateway)
10. [Binary Media Types (File Uploads)](#10-binary-media-types-file-uploads)
11. [Cold Starts](#11-cold-starts)
12. [Local Development with serverless-offline](#12-local-development-with-serverless-offline)
13. [Key Differences: EC2 vs Lambda+API Gateway](#13-key-differences-ec2-vs-lambdaapi-gateway)
14. [Glossary](#14-glossary)

---

## 1. Why We Moved Away From EC2

### The Original Setup
The project originally ran as a **traditional Express.js server on EC2** (or similar always-on compute). The `server.js` file tells this story clearly:

```js
// server.js — the OLD way (EC2 style)
const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Server started on port ${PORT}`);
});
```

This server:
- Ran **24/7** whether requests came in or not
- Required someone to **provision, patch, and manage** the EC2 instance
- Cost money **at rest** (idle hours still billed)
- Required **manual scaling** (or Auto Scaling Groups with extra config)

### The Problem at Scale for This Project
Kerala Ayurveda is a business backend that integrates:
- **Zoho CRM** (lead/contact sync)
- **Zoom** (webhooks)
- **Shopify** (orders + webhooks)
- **TalentLMS** (course enrollment)
- **MySQL** (Sequelize ORM)

Traffic is **bursty and unpredictable** — not a constant high load. Paying for EC2 24/7 when most hours are idle is wasteful.

### Why Serverless Made Sense
| Pain Point (EC2) | Solution (Lambda + API Gateway) |
|---|---|
| Pay for idle compute | Pay only per request (first 1M free/month) |
| Manual scaling | AWS auto-scales to thousands of concurrent invocations |
| Server management, OS patches | AWS manages all infra |
| Port management, reverse proxy config | API Gateway handles all routing |
| Complex deployment pipeline | `serverless deploy` — one command |

---

## 2. What is AWS API Gateway?

AWS API Gateway is a **fully managed service** that acts as the "front door" for your backend. It:

- **Receives** incoming HTTP requests from the internet
- **Routes** them to the correct backend (Lambda, EC2, HTTP endpoint, etc.)
- **Returns** the response back to the client

Think of it as a managed **Nginx/reverse proxy** in the cloud, but with WAF, auth, throttling, caching, and monitoring built in.

```
Client (Browser/App)
       │
       ▼
  [API Gateway]  ←── The "front door"
       │
       ▼
  [AWS Lambda]   ←── Your actual code runs here
       │
       ▼
  [MySQL / Zoho / Shopify / etc.]
```

---

## 3. API Gateway Types

AWS offers **three types** of API Gateway. You'll see all three in the console:

### 3.1 REST API
- The **original, most feature-rich** type
- Supports: resources, methods, stages, authorizers, usage plans, caching
- More complex to configure but maximum control
- **This is what our project uses (via Serverless Framework)**

### 3.2 HTTP API
- Newer, **simpler and cheaper** (~70% cheaper than REST API)
- Fewer features (no usage plans, no AWS WAF integration, limited authorizers)
- Best for: simple Lambda backends, JWT auth, low-latency APIs
- Supports Lambda proxy integration only

### 3.3 WebSocket API
- For **real-time bidirectional** communication
- Manages connection state (connect, message, disconnect routes)
- Used for: chat apps, live dashboards, gaming, notifications

### When to Use Which?

| Use Case | Recommended Type |
|---|---|
| Full-featured REST API with auth, WAF, caching | REST API |
| Simple CRUD Lambda backend, cost-sensitive | HTTP API |
| Real-time features (chat, live updates) | WebSocket API |
| Our project (Kerala Ayurveda) | REST API (via Serverless) |

---

## 4. REST API — Deep Dive

When you open the AWS Console and create a REST API manually, you build it in **three layers**:

```
REST API
  └── Resource  (URL path like /users)
        └── Method  (HTTP verb like GET, POST)
              └── Integration  (what handles the request)
```

### 4.1 Resources

A **Resource** is simply a URL path segment. Everything starts from the **root resource `/`**.

```
/                     ← root resource (always exists)
├── /users            ← resource
│     ├── /users/{id} ← child resource with path parameter
├── /orders
└── /health
```

**Path Parameters** use `{paramName}` syntax:
- `/users/{userId}` → captures any value in that segment
- `/products/{category}/{productId}` → captures two values

**Creating a Resource in Console:**
1. Go to API Gateway → your API → Resources
2. Click "Create Resource"
3. Optionally enable "Configure as proxy resource" (more on this below)
4. Give it a Resource Name and Resource Path

### 4.2 Methods

Under each resource, you create **Methods** — these map to HTTP verbs:

| Method | Use Case |
|---|---|
| `GET` | Read / fetch data |
| `POST` | Create new data |
| `PUT` | Full update of an entity |
| `PATCH` | Partial update |
| `DELETE` | Delete an entity |
| `ANY` | Catches all HTTP methods (used in our project) |
| `OPTIONS` | CORS preflight (can be auto-created) |

**To create a Method in Console:**
1. Select a Resource
2. Click "Create Method"
3. Choose the HTTP verb
4. Choose the Integration Type

### 4.3 Integration Types

When you configure a Method, you must tell API Gateway **what to send the request to**. The options are:

#### Lambda Function
- Sends the request to a Lambda function
- Two sub-modes: **Lambda Proxy** (recommended) and **Lambda (non-proxy/custom)**

#### HTTP / HTTP Proxy
- Forwards the request to an external HTTP endpoint (your EC2, on-prem server, etc.)
- Useful for **migrating gradually** from EC2 to serverless

#### Mock
- API Gateway returns a fake response without calling any backend
- Great for prototyping or returning static responses

#### AWS Service
- Directly integrates with other AWS services (S3, DynamoDB, SQS, SNS, etc.)
- Example: upload directly to S3 without a Lambda middleman

#### VPC Link
- Routes traffic to resources inside a VPC (private EC2, ECS, etc.)

---

### 4.4 Lambda Proxy Integration — The Key Concept

This is the most important concept to understand. There are **two modes** for Lambda integration:

---

#### Mode 1: Lambda (Non-Proxy / Custom Integration) — The Complex Way

In this mode, **you** define exactly:
- What gets sent TO Lambda (via a mapping template)
- What API Gateway expects BACK from Lambda (via a response mapping)

You write **Velocity Template Language (VTL)** mapping templates:

```vtl
## Request mapping template
{
  "userId": "$input.params('userId')",
  "body": $input.json('$')
}
```

Lambda receives only what your template sends. Lambda must return EXACTLY the format API Gateway expects. You must manually configure:
- Request transformation
- Response transformation  
- Status code mappings
- Header mappings

This is **verbose, complex, and hard to maintain**. Every new field requires template updates.

---

#### Mode 2: Lambda Proxy Integration — The Simple Way (What We Use)

With Lambda Proxy Integration enabled, API Gateway says:

> "I'll pass the entire raw HTTP request to your Lambda, and your Lambda gives me back the full HTTP response."

API Gateway **automatically packages** the entire request into a standardized event object and sends it to Lambda:

```json
{
  "httpMethod": "POST",
  "path": "/api/users",
  "pathParameters": { "proxy": "api/users" },
  "queryStringParameters": { "page": "1" },
  "headers": {
    "Content-Type": "application/json",
    "Authorization": "Bearer eyJ..."
  },
  "body": "{\"name\": \"John\", \"email\": \"john@example.com\"}",
  "isBase64Encoded": false,
  "requestContext": {
    "stage": "prod",
    "requestId": "abc123",
    ...
  }
}
```

Lambda must return a response in this exact format:

```json
{
  "statusCode": 200,
  "headers": {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*"
  },
  "body": "{\"message\": \"User created\"}",
  "isBase64Encoded": false
}
```

**Key rules:**
- `body` must be a **string** (JSON.stringify'd), not an object
- `statusCode` is required
- API Gateway uses these values to construct the actual HTTP response sent to the client

**Why Proxy Integration is Great:**
- No VTL templates to maintain
- Lambda gets the full request context
- Lambda has full control over the response
- Works perfectly with frameworks like Express.js via `serverless-http`

---

## 5. How Lambda + API Gateway Work Together

```
1. User hits:  POST https://xyz.execute-api.ap-south-1.amazonaws.com/dev/api/orders

2. API Gateway receives the request
   └── Matches route: ANY /{proxy+}
   └── Integration: Lambda Proxy

3. API Gateway creates an event object:
   {
     httpMethod: "POST",
     path: "/api/orders",
     body: '{"product": "Ashwagandha", "qty": 2}',
     headers: { ... }
   }

4. Lambda is invoked with this event

5. serverless-http translates the event into an Express.js request object

6. Express.js routes to the correct controller:
   app.post('/api/orders', ordersController.create)

7. Controller does its thing (DB query, Zoho sync, etc.)

8. Express.js sends a response

9. serverless-http translates the Express response into the Lambda response format:
   {
     statusCode: 201,
     headers: { "Content-Type": "application/json" },
     body: '{"orderId": "ORD-123"}'
   }

10. Lambda returns this to API Gateway

11. API Gateway strips the envelope and sends the actual HTTP 201 response to the client
```

---

## 6. How We Configured It (Our Project)

### 6.1 The Old server.js — EC2 Style

The original `server.js` is a **traditional long-running HTTP server**:

```js
// EC2/traditional server — starts once and keeps listening
const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Server started on port ${PORT}`);
});
```

It also had elaborate startup logging (`[STARTUP]` logs) because startup time was a one-time cost paid when EC2 instance boots. It explicitly tested DB connection at startup.

### 6.2 The New lambda.js Entry Point

The Lambda entrypoint is just **5 lines**:

```js
// lambda.js
const serverless = require('serverless-http');
const app = require('./app');

module.exports.handler = serverless(app);
```

That's it. `serverless-http` wraps the Express `app` into a Lambda handler function. When Lambda is invoked with an API Gateway event, `serverless-http` translates it in and out of Express format.

The `app.js` is a **cleaned-up Express app** that does NOT call `app.listen()` — because there's no port to listen on in Lambda:

```js
// app.js — Lambda-compatible Express
const app = express();
// ... middleware and routes ...
module.exports = app;  // Just export, don't listen
```

### 6.3 serverless.yml Explained Line by Line

```yaml
service: kerala-ayurveda-backend   # Your service/project name

provider:
  name: aws
  runtime: nodejs20.x              # Lambda runtime
  region: ap-south-1               # Mumbai region
  profile: keralaayurveda          # AWS CLI profile (credentials)
  memorySize: 512                  # MB of RAM for Lambda (affects CPU too)
  timeout: 29                      # Max seconds before Lambda times out
                                   # (29s because API Gateway max is 30s)

  environment:                     # Env vars injected into Lambda runtime
    DB_HOST: ${env:DB_HOST, ''}    # Read from local .env, fallback to ''
    # ... all other secrets ...

  apiGateway:
    binaryMediaTypes:              # Tell API Gateway not to corrupt binary data
      - 'multipart/form-data'      # File uploads
      - '*/*'                      # Any binary content

functions:
  app:                             # Function name (can be anything)
    handler: lambda.handler        # File: lambda.js, export: handler
    events:
      - http:                      # This creates API Gateway REST API trigger
          path: /                  # Route: the root path
          method: ANY              # Accept ALL HTTP methods (GET/POST/PUT/DELETE/etc.)
          cors: true               # Auto-create OPTIONS method + CORS headers

      - http:
          path: /{proxy+}          # The magic catch-all! Routes EVERYTHING else
          method: ANY              # to the same Lambda function
          cors: true

plugins:
  - serverless-offline             # For local dev (simulates Lambda + API Gateway)

custom:
  serverless-offline:
    noPrependStageInUrl: true      # Don't add /dev/ prefix locally
```

### 6.4 How Requests Flow

```
Request: GET /api/products?category=oils

API Gateway evaluates routes:
  ├── path: /    → Does it match "/"? No (it's /api/products)
  └── path: /{proxy+} → Does it match? YES ✓
                         proxy = "api/products"

Lambda invoked with:
  event.path = "/api/products"
  event.pathParameters = { proxy: "api/products" }
  event.queryStringParameters = { category: "oils" }
  event.httpMethod = "GET"

serverless-http converts to Express req:
  req.path = "/api/products"
  req.query = { category: "oils" }
  req.method = "GET"

Express routes to:
  app.get('/api/products', productsController.list)

Response flows back through serverless-http → Lambda → API Gateway → Client
```

---

## 7. The Proxy+ Pattern — Why It Is the Magic

The `/{proxy+}` path in the serverless.yml is the **key to making a full Express app work behind API Gateway**.

Without it, you'd have to create a separate API Gateway resource + method for **every single route** in your Express app:

```
# Without /{proxy+} — you'd need to manually create all of these:
/api/users              GET, POST
/api/users/{id}         GET, PUT, DELETE
/api/orders             GET, POST
/api/orders/{id}        GET, PUT, DELETE
/api/products           GET, POST
# ... 50+ more routes
```

**With `/{proxy+}`**, a single API Gateway "catch-all" route sends everything to Lambda, and **Express handles all internal routing** itself. Much simpler.

The two routes we define:
```yaml
- path: /        # Handles exactly "/"
- path: /{proxy+}  # Handles everything else: /api/*, /health, /any/path/here
```

The `+` in `{proxy+}` means "greedy" — match one or more path segments. So:
- `/api/products` → matched, `proxy = api/products`
- `/api/orders/123/items` → matched, `proxy = api/orders/123/items`

---

## 8. serverless-http — The Glue Layer

`serverless-http` is the npm package that bridges the gap between Lambda events and Express.js.

Without it, you'd have to manually:
1. Parse the Lambda event into a Node.js `IncomingMessage` object
2. Create a fake `ServerResponse` object
3. Pass them through Express
4. Collect the response and format it back as a Lambda response

`serverless-http` does all of this for you:

```js
const serverless = require('serverless-http');
const app = require('./app');       // Your Express app

module.exports.handler = serverless(app);
// serverless(app) returns:
// async function handler(event, context) {
//   // translates event → req
//   // runs express
//   // translates res → lambda response format
// }
```

It also supports other frameworks: Fastify, Koa, Hapi, etc.

---

## 9. CORS in API Gateway

CORS (Cross-Origin Resource Sharing) is required when a browser on `example.com` calls your API on `api.example.com`.

In `serverless.yml`, `cors: true` automatically:
1. Creates an `OPTIONS` method on that route
2. Adds `Access-Control-Allow-Origin`, `Access-Control-Allow-Headers`, and `Access-Control-Allow-Methods` headers to responses

In `app.js`, we also have:
```js
app.use(cors());  // express cors middleware
```

Both are needed:
- API Gateway CORS handles the **preflight OPTIONS response**
- Express CORS middleware adds **CORS headers to actual responses**

---

## 10. Binary Media Types (File Uploads)

Standard API Gateway base64-encodes binary request bodies. If you're uploading files (`multipart/form-data`), API Gateway would mangle the binary data.

The `binaryMediaTypes` setting in `serverless.yml`:
```yaml
apiGateway:
  binaryMediaTypes:
    - 'multipart/form-data'
    - '*/*'
```

This tells API Gateway: "for these content types, treat the body as binary (base64 encode/decode it properly instead of treating it as plain text)."

`serverless-http` and `multer` (our file upload middleware) then handle decoding on the Lambda side.

---

## 11. Cold Starts

A **cold start** happens when Lambda needs to spin up a new execution environment (container) to handle a request. This takes an extra **100ms–2s** depending on:
- Runtime (Node.js is fast, Java is slow)
- Package size (smaller = faster)
- Memory allocated (more memory = more CPU = faster init)

**After the first invocation**, the container stays "warm" for ~15 minutes. Subsequent requests in that window have **no cold start**.

Notice in `app.js` we commented out the startup DB authenticate call:
```js
// NOTE: During local dev we might authenticate here, but for Lambda,
// the DB connection will be implicitly established on the first route query.
// It is better not to leave floating promises during cold starts.
```

This is a best practice: **don't block Lambda startup with DB connections**. Let the first actual query establish the connection.

Also note the `timeout: 29` in `serverless.yml`. API Gateway has a hard **30-second maximum timeout**. We set Lambda to 29s to avoid a race condition where Lambda runs slightly over 30s and API Gateway times out first (which gives a confusing error).

---

## 12. Local Development with serverless-offline

`serverless-offline` is a Serverless Framework plugin that **simulates API Gateway + Lambda on your local machine**:

```bash
npm run dev
# equivalently: serverless offline --noPrependStageInUrl
```

This starts a local HTTP server (default port 3000) that:
- Reads your `serverless.yml` for the route configuration
- Simulates the Lambda event format
- Runs `lambda.handler` like Lambda would
- Returns the response via simulated API Gateway

`noPrependStageInUrl: true` means routes are `/api/products` locally instead of `/dev/api/products` (which is what they'd be in AWS with the `dev` stage prefix).

---

## 13. Key Differences: EC2 vs Lambda+API Gateway

| Aspect | EC2 / Traditional Server | Lambda + API Gateway |
|---|---|---|
| **Entry point** | `server.js` with `app.listen(PORT)` | `lambda.js` exports a handler function |
| **Lifecycle** | Process runs 24/7 | Function runs only when invoked |
| **Scaling** | Manual or Auto Scaling Groups | Automatic, concurrent per request |
| **Pricing** | Per hour (instance type) | Per invocation + duration |
| **DB connection** | Established once at startup | Re-established on cold start |
| **Startup logs** | Important (one-time cost) | Less relevant (per-request cold start) |
| **Port** | Listens on `PORT` (8080, 3000, etc.) | No port — handler function called directly |
| **Deployment** | SSH, Ansible, CodeDeploy, etc. | `serverless deploy` |
| **Local dev** | `node server.js` or `nodemon` | `serverless offline` |
| **Max execution time** | Unlimited | 15 minutes (API GW limit: 30 seconds) |
| **State** | In-memory state persists between req | No in-memory state between invocations |

---

## 14. Glossary

| Term | Meaning |
|---|---|
| **API Gateway** | AWS managed service that receives HTTP requests and routes them to backends |
| **REST API** | The full-featured API Gateway type with resources, methods, stages |
| **HTTP API** | Newer, simpler, cheaper API Gateway type |
| **WebSocket API** | Real-time bidirectional API Gateway type |
| **Resource** | A URL path in API Gateway (e.g., `/users`, `/orders/{id}`) |
| **Method** | HTTP verb on a resource (GET, POST, PUT, DELETE, ANY, etc.) |
| **Integration** | What backend handles the request (Lambda, HTTP, Mock, AWS Service) |
| **Lambda Proxy Integration** | API Gateway passes full raw request to Lambda; Lambda returns full raw response |
| **Non-Proxy Integration** | API Gateway transforms request/response via VTL templates |
| **`{proxy+}`** | Greedy path parameter that matches any path segment(s) |
| **VTL** | Velocity Template Language — used for custom request/response mapping |
| **Cold Start** | First invocation latency when Lambda spins up a new container |
| **Warm Start** | Subsequent invocations using an already-running container |
| **serverless-http** | npm package that wraps Express.js to work as a Lambda handler |
| **serverless-offline** | Plugin to simulate API Gateway + Lambda locally |
| **Serverless Framework** | Tool that generates and deploys CloudFormation stacks for Lambda/API GW |
| **Stage** | Deployment environment in API Gateway (dev, staging, prod) |
| **CORS** | Browser security mechanism requiring explicit permission for cross-origin requests |
| **Binary Media Types** | API Gateway config to handle binary request/response bodies correctly |
