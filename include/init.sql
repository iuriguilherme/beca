-- Enable pgvector extension for embedding storage
CREATE EXTENSION IF NOT EXISTS "vector";

-- Create the prompts table with self-referencing parent-child relationships
CREATE TABLE IF NOT EXISTS prompts (
    -- Primary key using UUID
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Parent prompt reference (self-referencing foreign key)
    -- Genesis prompts use the special UUID '00000000-0000-0000-0000-000000000000'
    parent_id UUID NOT NULL,
    
    -- The actual prompt text
    prompt_text TEXT NOT NULL,
    
    -- Embedding vector for similarity comparison
    -- Using embeddinggemma (gemme-300m) which produces 768-dimensional vectors
    -- Common dimensions: embeddinggemma: 768, OpenAI ada-002: 1536, text-embedding-3-large: 3072
    embedding vector(768),
    
    -- Effectiveness metrics
    effectiveness_score NUMERIC(5, 4),  -- Score between 0 and 1 with 4 decimal places
    
    -- Metadata for additional information (flexible JSON structure)
    metadata JSONB DEFAULT '{}'::jsonb,
    
    -- Timestamps for tracking
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- Foreign key constraint for parent_id (self-referencing)
    -- Allows the special genesis UUID
    CONSTRAINT fk_parent_prompt 
        FOREIGN KEY (parent_id) 
        REFERENCES prompts(id) 
        ON DELETE RESTRICT,
    
    -- Check constraint to ensure non-null parent_id
    CONSTRAINT chk_parent_id_not_null CHECK (parent_id IS NOT NULL)
);

-- Insert the genesis prompt (the root of all prompts)
-- This is required before any other prompts can be inserted
INSERT INTO prompts (
    id, 
    parent_id, 
    prompt_text, 
    embedding,
    metadata
) VALUES (
    '5af4727c-0283-580d-a2e5-c78f0fcea5ce',
    '5af4727c-0283-580d-a2e5-c78f0fcea5ce',  -- Self-referencing for genesis
    'Genesis prompt - the root of all prompts',
    NULL,  -- No embedding for genesis
    '{"type": "genesis", "description": "Root prompt with no parent"}'::jsonb
) ON CONFLICT (id) DO NOTHING;

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_prompts_parent_id ON prompts(parent_id);
CREATE INDEX IF NOT EXISTS idx_prompts_created_at ON prompts(created_at);
CREATE INDEX IF NOT EXISTS idx_prompts_effectiveness ON prompts(effectiveness_score) WHERE effectiveness_score IS NOT NULL;

-- Create index for vector similarity search (using cosine distance)
CREATE INDEX IF NOT EXISTS idx_prompts_embedding_cosine 
    ON prompts 
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

-- Optional: Create index for L2 distance if needed
-- CREATE INDEX IF NOT EXISTS idx_prompts_embedding_l2 
--     ON prompts 
--     USING ivfflat (embedding vector_l2_ops)
--     WITH (lists = 100);

-- Create a function to automatically update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
begin
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
end;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update updated_at on row updates
CREATE TRIGGER update_prompts_updated_at
    BEFORE UPDATE ON prompts
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Example view to get prompt hierarchy (optional)
CREATE OR REPLACE VIEW prompt_hierarchy AS
WITH RECURSIVE prompt_tree AS (
    -- Base case: genesis prompt
    SELECT 
        id,
        parent_id,
        prompt_text,
        effectiveness_score,
        created_at,
        1 AS depth,
        ARRAY[id] AS path
    FROM prompts
    WHERE id = '5af4727c-0283-580d-a2e5-c78f0fcea5ce'
    
    UNION ALL
    
    -- Recursive case: child prompts
    SELECT 
        p.id,
        p.parent_id,
        p.prompt_text,
        p.effectiveness_score,
        p.created_at,
        pt.depth + 1,
        pt.path || p.id
    FROM prompts p
    INNER JOIN prompt_tree pt ON p.parent_id = pt.id
    WHERE (
        p.id != '5af4727c-0283-580d-a2e5-c78f0fcea5ce'
        AND
        p.id != '00000000-0000-0000-0000-000000000000'
    )
)
SELECT * FROM prompt_tree;
