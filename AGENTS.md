# AGENTS.md

## Project Overview

BECA (Best Agent Evolve) is a meta-prompting AI system using n8n workflows, PostgreSQL, and Ollama. The system implements a sophisticated multi-agent orchestration pattern where agents collaborate to generate optimized prompts and execute tasks.

## Architecture

The system uses a **seven-workflow orchestration pattern**:

1. **Orchestrator** (`orchestrator_v3`) - Main workflow coordinating the entire process
2. **Fetch Data** (`fetch_data_v3`) - Loads configuration from files (`config.json` and `meta_prompt.md`)
3. **Asserting Step** (`asserting_step_v3`) - Input validation and normalization
4. **First Prompt Generator** (`first_prompt_generator_v3`) - Meta-prompting agent
5. **Second Prompt Generator** (`second_prompt_generator_v3`) - Task executor agent
6. **Embedding Step** (`embedding_step_v3`) - Vector embedding generation
7. **Persistence Step** (`persistence_step_v3`) - Database storage

### Data Flow

```
User Input/Chat/Schedule/External Trigger
    ↓
[orchestrator_v3]
    ↓ (calls fetch_data_v3)
    ↓
[fetch_data_v3] - Loads configuration:
    • Reads config.json (model settings)
    • Reads meta_prompt.md (system prompt template)
    • Returns: model_first, model_second, model_embedding, system_prompt_first
    ↓
[asserting_step_v3] - Validates and injects defaults:
    • model_first (default: llama3.2:latest)
    • model_second (default: llama3.2:latest) 
    • model_embedding (default: embeddinggemma:latest)
    • sessionId (generates if missing)
    • user_prompt (detects chatInput, default: "Ignore this")
    • context (default: "None")
    • system_prompt_first (default: "You are a prompt generator")
    ↓
[first_prompt_generator_v3] - Meta-prompter agent:
    • Receives user_prompt and context
    • Generates optimized system_prompt_second for secondary agent
    • Returns: system_prompt_second, user_intent, key_requirements, optimization_notes
    ↓
[second_prompt_generator_v3] - Task executor:
    • Uses generated system_prompt_second
    • Executes actual user request
    • Returns response
    ↓
[embedding_step_v3] - Embedding generator:
    • Generates 768-dimensional vector from prompt
    • Uses embeddinggemma via Ollama
    • Formats for PostgreSQL vector storage
    ↓
[persistence_step_v3] - Database storage:
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
│   │   ├── orchestrator_v3.json
│   │   ├── fetch_data_v3.json
│   │   ├── asserting_step_v3.json
│   │   ├── first_prompt_generator_v3.json
│   │   ├── second_prompt_generator_v3.json
│   │   ├── embedding_step_v3.json
│   │   └── persistence_step_v3.json
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

### orchestrator_v3

**Purpose**: Main entry point and orchestration hub

**Triggers**:
- Manual execution (Execute workflow button)
- Chat message (webhook)
- Schedule (disabled by default)
- External workflow call

**Process**:
1. Calls fetch_data_v3 to load configuration
2. Calls Asserting Step → First Prompt Generator → Second Prompt Generator → Embedding Step → Persistence Step
3. Returns final output

### fetch_data_v3

**Purpose**: Configuration loader - reads settings from files

**Process**:
1. Reads `../uploads/config.json` for model configuration
2. Reads `../uploads/meta_prompt.md` for system prompt template
3. Extracts JSON from config file
4. Extracts text from markdown file
5. Merges and returns configuration data

**Output**:
```json
{
  "model_first": "qwen2.5:latest",
  "model_second": "qwen2.5:latest",
  "model_embedding": "embeddinggemma:latest",
  "system_prompt_first": "<content from meta_prompt.md>"
}
```

### asserting_step_v3

**Purpose**: Input validation and default injection

**Validates** (in order):
1. `model_first` - Injects "llama3.2:latest" if missing
2. `model_second` - Injects "llama3.2:latest" if missing
3. `model_embedding` - Injects "embeddinggemma:latest" if missing
4. `sessionId` - Generates random ID if missing
5. `chatInput` - Converts to `user_prompt` if present
6. `user_prompt` - Injects "Ignore this" if missing
7. `context` - Injects "None" if missing
8. `system_prompt_first` - Injects default if missing

**Pattern**: Each validation uses an IF node with two branches:
- **True branch**: Value exists, continues
- **False branch**: Goes to "Inject X" node that provides default

This ensures all downstream workflows receive valid, normalized data.

### first_prompt_generator_v3

**Purpose**: Meta-prompting agent that generates optimized system prompts

**Components**:
- **Prompt Engineer Agent**: LangChain agent with structured output
- **Ollama Chat Model**: Uses model_first from input (typically qwen2.5:latest)
- **Window Buffer Memory**: Maintains conversation context per sessionId
- **Structured Output Parser**: Enforces JSON schema output

**Input Schema**:
```json
{
  "sessionId": "string",
  "model_first": "string",
  "model_second": "string",
  "system_prompt_first": "string",
  "user_prompt": "string",
  "context": "string"
}
```

**Output Schema**:
```json
{
  "system_prompt_second": "string",
  "user_intent": "string",
  "key_requirements": ["string"],
  "optimization_notes": "string",
  "success": "boolean"
}
```

**Error Handling**: Uses Success/Error nodes to track execution status

### second_prompt_generator_v3

**Purpose**: Task executor using optimized prompt from first agent

**Components**:
- **Secondary AI Agent**: LangChain agent (no output parser)
- **Ollama Chat Model**: Uses model_second from input
- **Window Buffer Memory**: Maintains same sessionId context

**Input Requirements**:
- `model_second`: LLM model name
- `user_intent`: Original user request
- `system_prompt_second`: Optimized prompt from first agent
- `key_requirements`: Task requirements
- `optimization_notes`: Optimization notes
- `sessionId`: Session tracking ID

**Output**: Free-form response based on generated system prompt

### embedding_step_v3

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

**Model**: `embeddinggemma:latest`
- Produces 768-dimensional vectors
- Good quality for semantic similarity

**Input**:
```json
{
  "prompt": "string",
  "model_embedding": "embeddinggemma:latest",
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

### persistence_step_v3

**Purpose**: Store prompts and embeddings in PostgreSQL database

**Components**:
- **Prepare for Database**: Sets metadata
- **Assert parent_id**: Checks if input has parent_id, generates genesis UUID if missing
- **Assert id**: Checks if input has UUID, generates from parent_id + prompt_text if missing
- **Code in Python**: Generates UUIDs using uuid5
- **Merge**: Combines generated UUIDs with input data
- **Insert or Update Prompts**: PostgreSQL upsert operation

**Process**:
1. Receives data from embedding_step_v3
2. Creates `metadata` object with sessionId and model_embedding
3. Checks if `parent_id` field exists, generates genesis UUID if missing
4. Checks if `id` field exists, generates new UUID from parent_id + prompt_text if missing
5. Upserts record to `prompts` table

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
  "model_embedding": "embeddinggemma:latest",
  "sessionId": "string"
}
```

**Output**:
```json
{
  "id": "uuid",
  "parent_id": "<genesis-uuid>",
  "prompt_text": "string",
  "embedding": "[0.1,0.2,...]",
  "metadata": {"sessionId": "...", "model_embedding": "..."},
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

**Orchestrator → Fetch Data**:
- (no input required, reads from files)

**Fetch Data → Asserting Step**:
- `model_first`, `model_second`, `model_embedding`, `system_prompt_first`

**Asserting Step → First Prompt Generator**:
- All validated fields pass through

**First Prompt Generator → Second Prompt Generator**:
- `model_second` - LLM model name (passed through)
- `user_intent` - User's original task (extracted from `$json.user_intent`)
- `key_requirements` - Task requirements (extracted from `$json.key_requirements`)
- `optimization_notes` - Optimization notes (extracted from `$json.optimization_notes`)
- `sessionId` - Session tracking (passed through)
- `system_prompt_second` - Generated prompt (extracted from `$json.output.system_prompt_second`)

### Structured Output Parser

First prompt generator uses manual JSON schema:
```json
{
  "system_prompt_second": { "type": "string" },
  "user_intent": { "type": "string" },
  "key_requirements": { "type": "array", "items": { "type": "string" } },
  "optimization_notes": { "type": "string" }
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
   - Image: `postgres:18-alpine`
   - Purpose: Prompt storage with vector embeddings
   - Extensions: pgvector
   - Volume: `./instance/postgres_data`

2. **n8n Database** (port 5432)
   - Image: `postgres:18-alpine`
   - Purpose: n8n workflow and execution storage
   - Volume: `./instance/n8n_postgres_data`

### n8n Server

- Image: `n8nio/n8n:1.122.5`
- Port: 5678
- Volumes:
  - configs: `./instance/n8n_data`
  - workflows: `./include/uploads/workflows`
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

Current: **qwen2.5:latest** (via Ollama)
- Good structured output support
- Sufficient for meta-prompting tasks
- Balance of speed and capability

Fallback: **llama3.2:latest**
- Lighter model for simpler tasks
- Faster inference

Note: Smaller models (<3B) can cause empty output errors in structured parsing.

### Embedding Model

Current: **embeddinggemma:latest** (via Ollama)
- Produces 768-dimensional vectors
- Good semantic similarity quality
- Database configured for vector(768)

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
