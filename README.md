# BECA - Best (Agent) Evolve

Rebecca is an initiative inspired by Alpha Evolve by Google DeepMind.

This was meant to be named be(s)t-a-evolve.

## Overview

BECA is a meta-prompting AI system that uses collaborative agents to optimize prompts and execute tasks. The system employs a multi-workflow orchestration pattern where specialized agents work together to improve prompt quality through evolutionary tracking and performance measurement.

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────┐
│                     User Interface                      │
│  (Manual, Chat Webhook, Schedule, External Trigger)    │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────▼──────────────┐
        │  Orchestrator Workflow    │
        │  (coordinator)            │
        └────────┬──────────────────┘
                 │
        ┌────────▼──────────────┐
        │  Asserting Step       │
        │  (validator)          │
        └────────┬──────────────┘
                 │
        ┌────────▼──────────────┐
        │  First Generator      │
        │  (meta-prompter)      │
        └────────┬──────────────┘
                 │
        ┌────────▼──────────────┐
        │  Second Generator     │
        │  (task executor)      │
        └────────┬──────────────┘
                 │
        ┌────────▼──────────────┐
        │  Response + Storage   │
        │  (PostgreSQL)         │
        └───────────────────────┘
```

### How It Works

1. **Input Processing**: User provides a task via n8n UI, chat, or API
2. **Validation**: Asserting Step ensures all required fields exist with sensible defaults
3. **Prompt Optimization**: First agent analyzes the task and generates an optimized system prompt
4. **Task Execution**: Second agent executes the task using the optimized prompt
5. **Evolution Tracking**: Results stored in PostgreSQL with lineage tracking for continuous improvement

### Key Innovation

BECA implements **meta-prompting** - an AI that crafts better prompts for other AIs. The first agent is a "Prompt Engineer AI" that:
- Analyzes user intent
- Considers the target model's capabilities
- Generates structured, optimized system prompts
- Tracks key requirements and optimization strategies

This two-stage approach enables:
- Better task understanding
- Model-specific optimization
- Explainable prompt engineering
- Evolutionary improvement through genealogy tracking

## Technology Stack

### Core Services

- **n8n** (1.120.2): Workflow orchestration and agent coordination
- **PostgreSQL** (16 + pgvector): Prompt storage with vector similarity search
- **Ollama** (0.12.11): Local LLM inference (GPU-accelerated)
- **Docker Compose**: Container orchestration

### n8n Workflows (4 total)

1. **orchestrator_v1**: Main entry point, defines model and system prompts
2. **asserting_step_v1**: Validates inputs and injects defaults
3. **first_prompt_generator_v2**: Meta-prompting agent with structured output
4. **second_prompt_generator_v1**: Task execution agent with free-form output

### Database Features

- **pgvector extension**: Enables semantic similarity search on prompts
- **Genealogy tracking**: Self-referencing parent-child relationships
- **Effectiveness scoring**: Numeric performance metrics
- **Metadata storage**: Flexible JSONB for additional context
- **Recursive views**: Track prompt evolution trees

### AI Models

- Primary: **qwen2.5:3b** (good structured output, balanced performance)
- Fallback Ollama instance available on port 11435
- Window buffer memory for conversation continuity

## Quick Start

### Prerequisites

- Docker and Docker Compose
- NVIDIA GPU with CUDA support (for Ollama)
- At least 8GB RAM
- 10GB disk space for models

### Setup

1. **Clone repository**
   ```bash
   git clone <repository-url>
   cd beca
   ```

2. **Configure environment**
   ```bash
   cp include/env.example .env
   cp include/env.db.example .env.db
   ```
   
   Edit `.env` and `.env.db` with your desired credentials.

3. **Start services**
   ```bash
   docker-compose up -d
   ```

4. **Pull LLM model**
   ```bash
   docker exec -it beca_ollama ollama pull qwen2.5:3b
   ```

5. **Access n8n**
   - Open http://localhost:5678
   - Complete initial setup
   - Workflows auto-load from `./include/workflows/`

6. **Test the system**
   - Open `orchestrator_v1` workflow
   - Click "Execute workflow"
   - Check the output

### Service Access

- **n8n UI**: http://localhost:5678
- **Main PostgreSQL**: localhost:5433
- **n8n PostgreSQL**: localhost:5432
- **Ollama**: http://localhost:11434
- **Ollama Fallback**: http://localhost:11435

## Usage

### Via n8n UI

1. Navigate to http://localhost:5678
2. Open the `orchestrator_v1` workflow
3. Modify the Example Input node with your prompt
4. Click "Execute workflow"
5. View results in the Return node

### Via Chat Interface

The orchestrator includes a chat trigger (disabled by default):
1. Enable the "When chat message received" node
2. Use the webhook URL to send messages
3. Responses include optimized prompts and task results

### Via API

Execute workflows programmatically:
```bash
curl -X POST http://localhost:5678/webhook/<workflow-id> \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "your task here",
    "context": "additional context",
    "model": "qwen2.5:3b"
  }'
```

## Data Flow

```
Input: { prompt, context?, model?, sessionId? }
  ↓
Asserting Step (validates + defaults)
  ↓
{ model, prompt, context, sessionId, systemPrompt }
  ↓
First Generator (meta-prompting)
  ↓
{ systemPrompt, userIntent, keyRequirements, optimizationNotes }
  ↓
Second Generator (execution)
  ↓
{ output: "final response", success: true }
```

## Project Structure

```
beca/
├── docker-compose.yml       # Service definitions
├── .env                     # n8n configuration
├── .env.db                  # Database credentials
├── include/
│   ├── init.sql            # Database schema + genesis prompt
│   ├── workflows/          # n8n workflow JSON files
│   │   ├── orchestrator_v1.json
│   │   ├── asserting_step_v1.json
│   │   ├── first_prompt_generator_v2.json
│   │   ├── second_prompt_generator_v1.json
│   │   ├── embedding_step_v2.json
│   │   └── persistence_step_v2.json
│   ├── prompts/            # System prompts (future)
│   ├── custom/             # Custom n8n nodes
│   └── uploads/            # File storage
└── instance/               # Persistent data (gitignored)
    ├── postgres_data/      # Main database
    ├── n8n_postgres_data/  # n8n database
    ├── n8n_data/           # n8n configs
    └── ollama/             # Model storage
```

## Evolutionary Prompt System

The PostgreSQL database tracks prompt evolution:

### Genesis Prompt

Every prompt chain starts from a genesis prompt:
- UUID: `5af4727c-0283-580d-a2e5-c78f0fcea5ce`
- Self-referencing parent
- Root of all prompt genealogy

### Prompt Genealogy

```sql
-- Each prompt has:
- id: Unique identifier
- parent_id: References previous prompt
- prompt_text: The actual prompt
- embedding: vector(1536) for similarity
- effectiveness_score: Performance metric
- metadata: JSONB for flexible data
- created_at, updated_at: Timestamps
```

### Similarity Search

Find similar prompts using vector search:
```sql
SELECT * FROM prompts
ORDER BY embedding <=> query_embedding
LIMIT 10;
```

### Track Evolution

View prompt lineage:
```sql
SELECT * FROM prompt_hierarchy
WHERE path @> ARRAY['your-prompt-uuid']::UUID[];
```

## Development

### Adding New Workflows

1. Create workflow in n8n UI
2. Export as JSON
3. Place in `include/workflows/`
4. Reference in orchestrator or other workflows

### Modifying Agents

- **System prompts**: Edit in orchestrator's "Define System Prompt" node
- **Output schemas**: Modify Structured Output Parser nodes
- **Models**: Change in "Define Model" nodes or Example Input

### Database Queries

Connect to database:
```bash
docker exec -it beca_database psql -U your_user -d your_db
```

### Logs

View service logs:
```bash
docker-compose logs -f n8n
docker-compose logs -f postgres
docker-compose logs -f ollama
```

## Roadmap

- [ ] Effectiveness scoring automation
- [ ] Prompt A/B testing workflows
- [ ] Web UI for prompt genealogy visualization
- [ ] Multi-model comparison
- [ ] RAG integration for context enhancement
- [ ] Automated workflow evolution

## Troubleshooting

**n8n fails to start**:
- Check `N8N_ENCRYPTION_KEY` is set in `.env`
- Verify PostgreSQL is healthy: `docker-compose ps`

**Ollama model errors**:
- Ensure model is pulled: `docker exec -it beca_ollama ollama list`
- Check GPU availability: `docker exec -it beca_ollama nvidia-smi`

**Workflow execution fails**:
- Verify all required fields in input
- Check Ollama service is accessible
- Review n8n execution logs

**Structured output errors**:
- Upgrade to qwen2.5:3b or larger model
- Verify JSON schema in output parser
- Check system prompt isn't too complex

## License

Copyright (C) 2025 Iuri Guilherme

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.

See the [LICENSE](LICENSE) file for more details.

## Documentation

- [AGENTS.md](AGENTS.md) - Comprehensive technical documentation for AI coding agents
- Workflow JSON files contain inline comments and example data
- Database schema documented in `include/init.sql`

## Inspiration

This project draws inspiration from:
- **Alpha Evolve** (Google DeepMind) - Evolutionary optimization
- **Meta-prompting research** - AI-driven prompt engineering
- **n8n** - Low-code workflow automation
