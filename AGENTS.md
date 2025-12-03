# AGENTS.md

## Project Overview

BECA (Best Agent Evolve) is a meta-prompting AI system using n8n workflows, PostgreSQL, and Ollama. The system implements a sophisticated multi-agent orchestration pattern where agents collaborate to generate optimized prompts and execute tasks.

## Architecture

The system uses a **five-workflow orchestration pattern**:

1. **Orchestrator** (`orchestrator_v1`) - Main workflow coordinating the entire process
2. **Asserting Step** (`asserting_step_v1`) - Input validation and normalization
3. **First Prompt Generator** (`first_prompt_generator_v2`) - Meta-prompting agent
4. **Second Prompt Generator** (`second_prompt_generator_v1`) - Task executor agent
5. **Embedding Step** (`embedding_step_v2`) - Vector embedding generation
6. **Persistence Step** (`persistence_step_v2`) - Database storage

### Data Flow

```
User Input/Chat/Schedule/External Trigger
    ↓
[orchestrator_v1]
    ↓ Define Model (qwen2.5:3b)
    ↓ Define System Prompt (Prompt Engineer instructions)
    ↓
[asserting_step_v1] - Validates and injects defaults:
    • model (default: llama3.2)
    • sessionId (generates if missing)
    • prompt (detects chatInput, default: "Ignore this")
    • context (default: "None")
    • systemPrompt (default: "You are a prompt generator")
    ↓
[first_prompt_generator_v2] - Meta-prompter agent:
    • Receives user prompt and context
    • Generates optimized systemPrompt for secondary agent
    • Returns: systemPrompt, userIntent, keyRequirements, optimizationNotes
    ↓
[second_prompt_generator_v1] - Task executor:
    • Uses generated systemPrompt
    • Executes actual user request
    • Returns response
    ↓
[embedding_step_v2] - Embedding generator:
    • Generates 768-dimensional vector from prompt
    • Uses embeddinggemma via Ollama
    • Formats for PostgreSQL vector storage
    ↓
[persistence_step_v2] - Database storage:
    • Stores prompt and embedding in PostgreSQL
    • Uses pgvector for similarity search
```

## Setup Commands

- Start services: `docker-compose up -d`
- Stop services: `docker-compose down`
- View logs: `docker-compose logs -f n8n`
- Access n8n UI: `http://localhost:5678`
- Access Ollama: `http://localhost:11434`
- Access Ollama Fallback: `http://localhost:11435`

## Project Structure

```
beca/
├── docker-compose.yml          # Service orchestration
├── include/
│   ├── init.sql               # PostgreSQL schema with pgvector
│   ├── prompts/               # System prompts for agents
│   ├── workflows/             # n8n workflow JSON files
│   │   ├── orchestrator_v1.json
│   │   ├── asserting_step_v1.json
│   │   ├── first_prompt_generator_v2.json
│   │   ├── second_prompt_generator_v1.json
│   │   ├── embedding_step_v2.json
│   │   └── persistence_step_v2.json
│   ├── custom/                # Custom n8n nodes
│   └── uploads/               # Upload storage
├── instance/                  # Runtime data (volumes)
│   ├── postgres_data/         # Main database (pgvector)
│   ├── n8n_postgres_data/     # n8n database
│   ├── n8n_data/              # n8n configuration
│   └── ollama/                # Ollama models
└── .env, .env.db             # Environment configuration
```

## Workflows

### orchestrator_v1

**Purpose**: Main entry point and orchestration hub

**Triggers**:
- Manual execution (Execute workflow button)
- Chat message (webhook)
- Schedule (disabled by default)
- External workflow call

**Process**:
1. Defines model configuration (qwen2.5:3b)
2. Defines system prompt for meta-prompting
3. Calls Asserting Step → First Prompt Generator → Second Prompt Generator
4. Returns final output

### asserting_step_v1

**Purpose**: Input validation and default injection

**Validates** (in order):
1. `model` - Injects "llama3.2" if missing
2. `sessionId` - Generates random ID if missing
3. `chatInput` - Converts to `prompt` if present
4. `prompt` - Injects "Ignore this" if missing
5. `context` - Injects "None" if missing
6. `systemPrompt` - Injects default if missing

**Pattern**: Each validation uses an IF node with two branches:
- **True branch**: Value exists, continues
- **False branch**: Goes to "Inject X" node that provides default

This ensures all downstream workflows receive valid, normalized data.

### first_prompt_generator_v2

**Purpose**: Meta-prompting agent that generates optimized system prompts

**Components**:
- **Prompt Engineer Agent**: LangChain agent with structured output
- **Ollama Chat Model**: Uses model from input (typically qwen2.5:3b)
- **Window Buffer Memory**: Maintains conversation context per sessionId
- **Structured Output Parser**: Enforces JSON schema output

**Input Schema**:
```json
{
  "model": "string",
  "prompt": "string",
  "context": "string",
  "sessionId": "string",
  "systemPrompt": "string"
}
```

**Output Schema**:
```json
{
  "systemPrompt": "string",
  "userIntent": "string",
  "keyRequirements": "array<string>",
  "optimizationNotes": "string",
  "success": "boolean"
}
```

**Error Handling**: Uses Success/Error nodes to track execution status

### second_prompt_generator_v1

**Purpose**: Task executor using optimized prompt from first agent

**Components**:
- **Secondary AI Agent**: LangChain agent (no output parser)
- **Ollama Chat Model**: Uses model from orchestrator
- **Window Buffer Memory**: Maintains same sessionId context

**Input Requirements**:
- `model`: LLM model name
- `userPrompt`: Original user request
- `systemPrompt`: Optimized prompt from first agent
- `sessionId`: Session tracking ID

**Output**: Free-form response based on generated system prompt

### embedding_step_v2

**Purpose**: Generate vector embeddings from prompts for similarity search

**Components**:
- **HTTP Request**: Calls Ollama embeddings API directly
- **Format Embedding**: Converts array to PostgreSQL vector format
- **Merge**: Combines original input with generated embedding

**Process**:
1. Receives prompt text from previous workflow
2. Sends to Ollama embeddings endpoint (`/api/embeddings`)
3. Gets 768-dimensional vector array
4. Formats as PostgreSQL vector string: `[0.123,0.456,...]`
5. Merges with original input data
6. Passes to persistence workflow

**Model**: `embeddinggemma`
- Produces 768-dimensional vectors
- Good quality for semantic similarity
- Note: Model may be specified as "embeddinggemma:300m" but outputs 768 dimensions

**Input**:
```json
{
  "prompt": "string",
  "embeddingModel": "embeddinggemma:300m",
  "sessionId": "string"
}
```

**Output**:
```json
{
  "prompt": "string",
  "prompt_text": "string",
  "embedding": "[0.1,0.2,0.3,...]",  // 768 floats
  "embeddingModel": "embeddinggemma:300m",
  "sessionId": "string",
  "success": true
}
```

### persistence_step_v2

**Purpose**: Store prompts and embeddings in PostgreSQL database

**Components**:
- **Prepare for Database**: Sets parent_id and metadata
- **Assert id**: Checks if input has UUID, generates if missing
- **Code in Python**: Generates new UUID when needed
- **Merge**: Combines generated UUID with input data
- **Insert or Update Prompts**: PostgreSQL upsert operation

**Process**:
1. Receives data from embedding_step_v2
2. Sets `parent_id` to genesis UUID (5af4727c-0283-580d-a2e5-c78f0fcea5ce)
3. Creates `metadata` object with sessionId and embeddingModel
4. Checks if `id` field exists
5. If no `id`, generates new UUID and merges with data
6. Upserts record to `prompts` table

**Database Fields**:
- `id`: UUID (auto-generated if not provided)
- `parent_id`: UUID (defaults to genesis)
- `prompt_text`: TEXT (the prompt that was embedded)
- `embedding`: vector(768) (PostgreSQL vector format)
- `metadata`: JSONB (session and model info)
- `effectiveness_score`: NUMERIC (optional, defaults to 0)
- `created_at`, `updated_at`: Timestamps (auto-managed)

**Input**:
```json
{
  "prompt_text": "string",
  "embedding": "[0.1,0.2,...]",
  "embeddingModel": "embeddinggemma:300m",
  "sessionId": "string"
}
```

**Output**:
```json
{
  "id": "uuid",
  "parent_id": "5af4727c-0283-580d-a2e5-c78f0fcea5ce",
  "prompt_text": "string",
  "embedding": "[0.1,0.2,...]",
  "metadata": {"sessionId": "...", "embeddingModel": "..."},
  "success": true
}
```

## Important Files
Each workflow includes:
- Manual trigger for standalone testing
- Example Input node with test data
- Success/Error handlers for debugging

To test:
1. Open workflow in n8n
2. Click "Execute workflow" button
3. Verify output in Return node

## Code Conventions

### Workflow JSON Structure

- **DO NOT** modify Example Input, Success, or Error nodes unless absolutely necessary
- **DO** make output compatibility changes in Return nodes
- Use `includeOtherFields: true` to pass through data
- Extract nested fields explicitly (e.g., `$json.output.systemPrompt`)

### Field Mapping

**Orchestrator → Asserting Step**:
- `model`, `systemPrompt`, `prompt`, `context`, `sessionId`

**Asserting Step → First Prompt Generator**:
- All validated fields pass through

**First Prompt Generator → Second Prompt Generator**:
- `model` - LLM model name (passed through)
- `userPrompt` - User's original task (extracted from `$json.userPrompt`)
- `sessionId` - Session tracking (passed through)
- `systemPrompt` - Generated prompt (extracted from `$json.output.systemPrompt`)

### Structured Output Parser

First prompt generator uses manual JSON schema:
```json
{
  "systemPrompt": { "type": "string" },
  "userIntent": { "type": "string" },
  "keyRequirements": { "type": "array", "items": { "type": "string" } },
  "optimizationNotes": { "type": "string" }
}
```

Second prompt generator uses no output parser (free-form response).

## Database Schema

The `prompts` table uses:
- UUID primary keys with `gen_random_uuid()`
- Self-referencing `parent_id` for prompt genealogy
- `vector(768)` for embeddings using embeddinggemma (pgvector extension required)
- Genesis prompt: `5af4727c-0283-580d-a2e5-c78f0fcea5ce`
- JSONB `metadata` field for flexible storage
- `effectiveness_score` NUMERIC(5,4) for tracking performance
- IVFFlat index for vector similarity search (cosine distance)

### Prompt Hierarchy

The database supports evolutionary prompt tracking:
- Genesis prompt is self-referencing (parent_id = own id)
- All prompts must have a parent (enforced by foreign key)
- Recursive CTE view (`prompt_hierarchy`) for tree traversal
- Tracks depth and path through prompt evolution

## Services

### PostgreSQL Databases

1. **Main Database** (port 5433)
   - Image: `pgvector/pgvector:pg16`
   - Purpose: Prompt storage with vector embeddings
   - Extensions: pgvector
   - Volume: `./instance/postgres_data`

2. **n8n Database** (port 5432)
   - Image: `postgres:15-alpine`
   - Purpose: n8n workflow and execution storage
   - Volume: `./instance/n8n_postgres_data`

### n8n Server

- Image: `n8nio/n8n:1.120.2`
- Port: 5678
- Volumes:
  - configs: `./instance/n8n_data`
  - workflows: `./include/workflows`
  - custom nodes: `./include/custom/dist`
  - uploads: `./include/uploads`

### Ollama

1. **Primary Ollama** (port 11434)
   - GPU-accelerated
   - Models storage shared between instances

2. **Fallback Ollama** (port 11435)
   - GPU-accelerated
   - Separate data, shared models

Both require NVIDIA GPU with CUDA support.

## Model Configuration

### Chat Models

Current: **qwen2.5:3b** (via Ollama)
- Good structured output support
- Sufficient for meta-prompting tasks
- Balance of speed and capability

Note: `llama3.2:1b` is too small - causes empty output errors.

### Embedding Model

Current: **embeddinggemma** (via Ollama)
- Produces 768-dimensional vectors
- Good semantic similarity quality
- Database configured for vector(768)
- Note: Model name may show as "embeddinggemma:300m" but outputs 768 dimensions

## Common Issues

**Structured output parser errors**: 
- Use `schemaType: "manual"` with JSON schema
- Ensure schema defines all required fields with types
- Verify model supports structured output (use qwen2.5:3b+)

**Agent output incompatibility**:
- Check Return node extracts from `$json.output.*` 
- Verify field names match between workflows
- Ensure `includeOtherFields: true` is set

**Model failures**:
- Use qwen2.5:3b or larger
- Avoid overly complex system prompts
- Check Ollama service is running and model is pulled

**SessionId not maintained**:
- Verify sessionId flows through all workflows
- Check Window Buffer Memory uses `sessionKey: "={{ $json.sessionId }}"`
- Ensure Asserting Step generates sessionId if missing

## Environment Variables

See `.env.example` and `.env.db.example` for required variables:

**Database** (.env.db):
- `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`

**n8n** (.env):
- `N8N_ENCRYPTION_KEY` - Must be set for n8n to function
- `N8N_HOST`, `N8N_PORT` - Server configuration
- `N8N_PROTOCOL`, `WEBHOOK_URL` - Webhook configuration
- `POSTGRES_*` - Database credentials for n8n's own database

**Ollama**:
- Configured via n8n credentials in UI
- Default: `http://ollama:11434` (internal Docker network)

## Key Insights

1. **Separation of Concerns**: Each workflow has a single responsibility:
   - Orchestrator: coordination
   - Asserting Step: validation
   - First Generator: prompt engineering
   - Second Generator: task execution

2. **Fail-Safe Defaults**: Asserting Step ensures workflows never fail due to missing inputs

3. **Session Continuity**: SessionId flows through all workflows, enabling conversation memory

4. **Structured Meta-Prompting**: First agent uses structured output to ensure consistent, parseable prompt generation

5. **Flexible Task Execution**: Second agent uses free-form output for natural responses

6. **Evolutionary Tracking**: Database schema supports tracking prompt lineage and effectiveness over time
