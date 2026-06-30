Rails.application.routes.draw do
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
  resources :sd_model_profiles
  resources :lora_profiles
  resources :prompt_styles
  resources :image_generations, only: %i[index show new create destroy] do
    member do
      post :refine
    end

    collection do
      post :translate_prompt
    end
  end
  resources :img2img_generations, only: %i[index show new create destroy] do
    collection do
      post :translate_prompt
    end
  end

  post "sd_prompt_token_count", to: "sd_prompt_tokens#create", as: :sd_prompt_token_count

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
