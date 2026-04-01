-- Create developer_apps table for storing OAuth applications
CREATE TABLE developer_apps (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) NOT NULL,
  app_name TEXT NOT NULL,
  description TEXT,
  app_url TEXT NOT NULL,
  redirect_uris TEXT NOT NULL,
  client_id TEXT NOT NULL UNIQUE,
  client_secret TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE developer_apps ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Developers can view their own apps" ON developer_apps
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Developers can create their own apps" ON developer_apps
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Developers can update their own apps" ON developer_apps
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Developers can delete their own apps" ON developer_apps
  FOR DELETE USING (auth.uid() = user_id);

-- Create indexes for better performance
CREATE INDEX idx_developer_apps_user_id ON developer_apps(user_id);
CREATE INDEX idx_developer_apps_client_id ON developer_apps(client_id);

-- Function to generate secure client_id and client_secret
CREATE OR REPLACE FUNCTION generate_client_credentials()
RETURNS TABLE(client_id TEXT, client_secret TEXT) AS $$
DECLARE
  new_client_id TEXT;
  new_client_secret TEXT;
BEGIN
  -- Generate unique client_id (24 characters)
  new_client_id := 'op_' || encode(gen_random_bytes(16), 'hex');
  
  -- Generate secure client_secret (32 characters)
  new_client_secret := encode(gen_random_bytes(24), 'hex');
  
  -- Ensure client_id is unique
  WHILE EXISTS (SELECT 1 FROM developer_apps WHERE client_id = new_client_id) LOOP
    new_client_id := 'op_' || encode(gen_random_bytes(16), 'hex');
  END LOOP;
  
  RETURN QUERY SELECT new_client_id, new_client_secret;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to register a new app
CREATE OR REPLACE FUNCTION register_developer_app(
  p_app_name TEXT,
  p_description TEXT DEFAULT NULL,
  p_app_url TEXT,
  p_redirect_uris TEXT
)
RETURNS TABLE(
  id UUID,
  client_id TEXT,
  client_secret TEXT,
  app_name TEXT,
  description TEXT,
  app_url TEXT,
  redirect_uris TEXT,
  created_at TIMESTAMP WITH TIME ZONE
) AS $$
DECLARE
  new_app_id UUID;
  new_client_id TEXT;
  new_client_secret TEXT;
BEGIN
  -- Generate client credentials
  SELECT client_id, client_secret INTO new_client_id, new_client_secret
  FROM generate_client_credentials();
  
  -- Insert the new app
  INSERT INTO developer_apps (
    user_id,
    app_name,
    description,
    app_url,
    redirect_uris,
    client_id,
    client_secret
  ) VALUES (
    auth.uid(),
    p_app_name,
    p_description,
    p_app_url,
    p_redirect_uris,
    new_client_id,
    new_client_secret
  ) RETURNING id INTO new_app_id;
  
  -- Return the created app details
  RETURN QUERY
  SELECT 
    da.id,
    da.client_id,
    da.client_secret,
    da.app_name,
    da.description,
    da.app_url,
    da.redirect_uris,
    da.created_at
  FROM developer_apps da
  WHERE da.id = new_app_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get user's apps
CREATE OR REPLACE FUNCTION get_user_developer_apps()
RETURNS TABLE(
  id UUID,
  app_name TEXT,
  description TEXT,
  app_url TEXT,
  redirect_uris TEXT,
  client_id TEXT,
  created_at TIMESTAMP WITH TIME ZONE,
  updated_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    da.id,
    da.app_name,
    da.description,
    da.app_url,
    da.redirect_uris,
    da.client_id,
    da.created_at,
    da.updated_at
  FROM developer_apps da
  WHERE da.user_id = auth.uid()
  ORDER BY da.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to delete developer app
CREATE OR REPLACE FUNCTION delete_developer_app(p_app_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM developer_apps 
  WHERE id = p_app_id AND user_id = auth.uid();
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count > 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update timestamp trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for updated_at
CREATE TRIGGER update_developer_apps_updated_at
  BEFORE UPDATE ON developer_apps
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
