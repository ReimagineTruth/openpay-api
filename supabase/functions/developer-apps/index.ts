import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { corsHeaders } from "../_shared/cors.ts"

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey)
    
    // Get the user from the request
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabase.auth.getUser(token)

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authorization token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const url = new URL(req.url)
    const method = req.method

    // Handle different HTTP methods
    switch (method) {
      case 'POST':
        return await handleRegisterApp(req, supabase, user.id)
      case 'GET':
        return await handleGetApps(supabase, user.id)
      case 'DELETE':
        return await handleDeleteApp(url, supabase, user.id)
      default:
        return new Response(
          JSON.stringify({ error: 'Method not allowed' }),
          { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
  } catch (error) {
    console.error('Error in developer-apps function:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

async function handleRegisterApp(req: Request, supabase: any, userId: string) {
  try {
    const { app_name, description, app_url, redirect_uris } = await req.json()

    // Validate required fields
    if (!app_name || !app_url || !redirect_uris) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: app_name, app_url, redirect_uris' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate URL format
    try {
      new URL(app_url)
    } catch {
      return new Response(
        JSON.stringify({ error: 'Invalid app_url format' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate redirect URIs (comma-separated)
    const redirectUris = redirect_uris.split(',').map((uri: string) => uri.trim())
    for (const uri of redirectUris) {
      try {
        new URL(uri)
      } catch {
        return new Response(
          JSON.stringify({ error: `Invalid redirect URI format: ${uri}` }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // Call the register_developer_app function
    const { data, error } = await supabase.rpc('register_developer_app', {
      p_app_name: app_name,
      p_description: description || null,
      p_app_url: app_url,
      p_redirect_uris: redirect_uris.join(',')
    })

    if (error) {
      console.error('Error registering app:', error)
      return new Response(
        JSON.stringify({ error: 'Failed to register app', details: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ 
        success: true,
        app: data[0] // Return the first row from the result
      }),
      { status: 201, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error in handleRegisterApp:', error)
    return new Response(
      JSON.stringify({ error: 'Invalid request body' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
}

async function handleGetApps(supabase: any, userId: string) {
  try {
    const { data, error } = await supabase.rpc('get_user_developer_apps')

    if (error) {
      console.error('Error fetching apps:', error)
      return new Response(
        JSON.stringify({ error: 'Failed to fetch apps', details: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ 
        success: true,
        apps: data || []
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error in handleGetApps:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
}

async function handleDeleteApp(url: URL, supabase: any, userId: string) {
  try {
    const appId = url.searchParams.get('id')
    
    if (!appId) {
      return new Response(
        JSON.stringify({ error: 'Missing app ID parameter' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate UUID format
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    if (!uuidRegex.test(appId)) {
      return new Response(
        JSON.stringify({ error: 'Invalid app ID format' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { data, error } = await supabase.rpc('delete_developer_app', {
      p_app_id: appId
    })

    if (error) {
      console.error('Error deleting app:', error)
      return new Response(
        JSON.stringify({ error: 'Failed to delete app', details: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!data) {
      return new Response(
        JSON.stringify({ error: 'App not found or you do not have permission to delete it' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ 
        success: true,
        message: 'App deleted successfully'
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error in handleDeleteApp:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
}
