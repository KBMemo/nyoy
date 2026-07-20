Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  resources :chats do
    member do
      post :cancel
      patch :chat_settings, action: :update_chat_settings
    end
    resources :messages, only: [ :create ]
    resources :agent_runs, only: [ :show ] do
      member do
        post :approve
        post :reject
        post :retry
      end
    end
  end
  resources :models, only: [ :index, :show ] do
    collection do
      post :refresh
    end
  end
  root "memo_illustrations#index"

  resources :memo_illustrations, only: %i[index show new create destroy] do
    member do
      get :inpaint
      post :inpaint, action: :create_inpaint
      post :translate_inpaint_note
      get :progress
      delete "inpainted_images/:attachment_id", action: :destroy_inpainted_image, as: :inpainted_image
    end
  end
  resources :prompt_knowledge_chunks
  resources :service_connections do
    collection do
      post :seed_missing
      get :llama_servers
      post :operate_llama_server
    end
    member do
      patch :bind_llama_server
      post :sync_llama_server
      post :refresh_models
      post :load_sampling
      patch :openai_chat_models
    end
  end
  resources :llama_servers, only: %i[new create edit update destroy]
  resources :llm_sampling_presets
  resource :app_settings, only: %i[edit update]
  resources :sd_model_profiles
  resources :sd_prompt_templates
  resources :lora_profiles
  resources :prompt_styles
  resources :image_generations, only: %i[index show new create destroy] do
    member do
      post :refine
    end

    collection do
      post :translate_prompt
      post :generate_prompt_direct
      get :samplers
    end
  end
  resources :img2img_generations, only: %i[index show new create destroy] do
    collection do
      post :translate_prompt
    end
  end
  resources :image_understandings, only: %i[new create]

  post "sd_prompt_token_count", to: "sd_prompt_tokens#create", as: :sd_prompt_token_count
  post "generation_memo_saves", to: "generation_memo_saves#create", as: :generation_memo_saves

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  match "mcp", to: "mcp#entry", via: %i[get post delete], as: :mcp

  namespace :webhooks do
    namespace :kbmemo do
      post "memos", to: "memos#create", as: :memos
    end
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
