-- ==============================================================================
-- Database Initialization for OWASP Dependency-Track
-- ==============================================================================

-- Create extension if needed
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Ensure timezone is set to UTC
SET timezone = 'UTC';
