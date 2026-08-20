Rails.application.routes.draw do
  devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks", confirmations: "users/confirmations", registrations: "users/registrations", passwords: "users/passwords" }, skip: [ :registrations ]
  devise_scope :user do
    post "/users", to: "users/registrations#create", as: :user_registration
    delete "/users", to: "users/registrations#destroy"
    post "/users/cancel", to: "users/registrations#cancel", as: :cancel_user_registration
    get "/users/sign_up", to: "users/registrations#new", as: :new_user_registration
    get "/users/sign_up/check_email", to: "users/registrations#check_email", as: :signup_check_email
    patch "/users", to: "users/registrations#update"
    put "/users", to: "users/registrations#update"
  end

  # Account restoration. Used by the one-time link in the
  # account-pending-deletion email; valid for 90 days from soft-delete.
  get  "/account/restore", to: "users/account_restorations#show",   as: :account_restoration
  post "/account/restore", to: "users/account_restorations#update"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # SAML metadata and SSO initiation endpoints. The metadata endpoint is
  # public (IdPs need to fetch it anonymously); the initiation endpoint is
  # safe to hit without auth (it redirects to the IdP).
  get  "/saml/metadata/:slug", to: "saml_metadata#show", as: :saml_metadata,
       constraints: { slug: /[a-z0-9][a-z0-9\-]*/ }
  get  "/auth/sso", to: "sso_initiations#new", as: :sso_initiation

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  get "/favicon.ico", to: redirect("/favicon.svg")

  # Sitemap for search engines
  get "sitemap.xml", to: "sitemap#show", as: :sitemap, defaults: { format: :xml }

  # IndexNow verification endpoint for instant indexing (Bing, Yandex, etc.)
  get ":key.txt", to: "index_now#verify", constraints: { key: /[a-z0-9\-]+/ }

  # Sidekiq Web UI in development
  if Rails.env.development?
    require "sidekiq/web"
    mount Sidekiq::Web => "/sidekiq"
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  # API Documentation (Swagger UI)
  get "/api/docs", to: "api_docs#index", as: :api_docs
  get "/api/docs/spec.json", to: "api_docs#spec", as: :api_docs_spec

  # User Documentation
  resources :docs, only: [ :index ], path: "docs" do
    get ":category", to: "docs#category", as: :category, on: :collection
    get ":category/:slug", to: "docs#show", as: :page, on: :collection
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Onboarding wizard (full-screen, no sidebar)
  get "/onboarding", to: "onboarding#show", as: :onboarding
  post "/onboarding/organization", to: "onboarding#create_organization", as: :onboarding_create_organization
  patch "/onboarding/organization", to: "onboarding#update_organization", as: :onboarding_update_organization
  post "/onboarding/token", to: "onboarding#create_token", as: :onboarding_create_token
  post "/onboarding/advance", to: "onboarding#advance", as: :onboarding_advance
  post "/onboarding/skip", to: "onboarding#skip", as: :onboarding_skip
  get "/onboarding/complete", to: "onboarding#complete", as: :onboarding_complete

  # Root routing based on authentication
  authenticated :user do
    root to: "home#index", as: :authenticated_root
  end

  unauthenticated do
    root to: "landing#index", as: :unauthenticated_root
  end

  # Contact form
  resources :contacts, only: [ :create ]

  get "/pricing", to: "pricing#show", as: :pricing
  get "/terms-and-conditions", to: "legal#terms", as: :terms_of_service
  get "/privacy-policy", to: "legal#privacy", as: :privacy_policy
  get "/refund-policy", to: "legal#refund", as: :refund_policy
  resource :settings, only: :show
  resource :notification_preferences, only: [ :show, :update ], path: "/settings/notifications"
  namespace :billing do
    # User-initiated end of the 14-day reverse trial. Drops the user to
    # Free immediately. Doesn't go through Paddle because trial users
    # have no Paddle subscription -- the trial is tracked on the User row.
    resource :trial, only: :destroy, controller: "trials"

    namespace :paddle do
      post :checkout_complete, to: "checkout_events#create"
      post :portal_session, to: "portal_sessions#create"
      post :subscription_change_preview, to: "subscription_change_previews#create"
      post :subscription_change, to: "subscription_changes#create"
      delete :scheduled_change, to: "scheduled_changes#destroy"
      post :webhooks, to: "webhooks#create"
    end
  end

  resources :notifications, only: [ :index ] do
    collection do
      post :mark_all_as_read
      get :dropdown
    end
    member do
      get :click
      post :mark_as_read
      delete :dismiss
    end
  end

  resources :organizations do
    member do
      post :switch
      post :sync
      get :sync_status
      post :sync_google_play
      get :sync_status_google_play
      post :sync_all
      get :sync_status_all
    end
    # Per-job dismiss: clears a single OrgSyncRun row so the dashboard
    # error card goes away. Used as the "unstick me, I don't care
    # anymore" escape hatch when a stranded run keeps re-stranding and
    # plain Retry isn't fixing it.
    resources :sync_runs, only: :destroy, param: :job_name,
              controller: "organizations/sync_runs",
              constraints: { job_name: /[a-z_]+/ }
    resources :memberships, only: [ :create, :update, :destroy ]
    resources :organization_invitations, only: [ :create ]
    resources :app_store_connect_credentials, only: [ :create, :destroy ] do
      post :activate, on: :member
      post :test, on: :member
    end
    resources :apple_certificates, only: [ :index, :show ] do
      get :download, on: :member
    end
    resources :apple_devices, only: [ :index, :create, :update ]
    resources :apple_bundle_ids, only: [ :index, :show, :new, :create ] do
      member do
        post :enable_capability
        delete :disable_capability
        post :register_app_group
        post :associate_app_group
        delete :dissociate_app_group
      end
    end
    resources :apple_provisioning_profiles, only: [ :index, :show, :new, :create, :destroy ] do
      member do
        get :download
        post :regenerate
      end
    end
    resources :android_keystores, except: [ :edit ] do
      get :download, on: :member
      post :validate, on: :collection
      post :activate, on: :member
    end
    resources :android_apps, only: [ :index, :show, :new, :create ] do
      get :releases, on: :member
    end
    resources :android_tracks, only: [ :index ]
    resources :apple_apps, only: [ :index, :show ] do
      get :releases, on: :member
      resources :tracked_keywords, only: [ :create, :destroy, :show ]
      resources :saved_keyword_ideas, only: [ :create, :destroy ] do
        delete :clear_all, on: :collection
      end
    end
    resources :testflight_beta_groups, only: [ :index ]
    resources :api_tokens, only: [ :index, :new, :create, :destroy ]
    resources :app_store_releases
    resources :android_releases, only: [ :edit, :update, :destroy ]
    resources :google_play_credentials, only: [ :create, :destroy ] do
      post :activate, on: :member
      post :test, on: :member
    end
    resource :apple_ads_credential, only: [ :new, :create, :edit, :update, :destroy ]
    # Navigation restructure: new feature pages
    resource :signing_assets, only: [ :show ], controller: "signing_assets"

    # Releases is the unified hub for store listing metadata, release notes,
    # builds, submission state, and pre-submission checklists. It replaces the
    # old separate StoreListings and ReleaseNotes controllers.
    resources :releases, only: [ :index, :show, :update ] do
      member do
        post :sync
        get  :sync_status
        post :push
        post :translate
        post :add_locale
        post :create_listing

        # Submission tab actions
        post :submit_to_store
        post :refresh_validation_errors

        # What's New tab actions (release note CRUD + workflow)
        post   :create_release_note,    path: "release_notes"
        patch  :update_release_note,    path: "release_notes/:note_id"
        put    :update_release_note,    path: "release_notes/:note_id"
        delete :destroy_release_note,   path: "release_notes/:note_id"
        post   :translate_release_note, path: "release_notes/:note_id/translate"
        post   :rewrite_release_note,   path: "release_notes/:note_id/rewrite"
        post   :apply_release_note,     path: "release_notes/:note_id/apply"
        patch  :update_release_translation, path: "release_notes/:note_id/translations/:locale",
               constraints: { locale: %r{[A-Za-z0-9\-]+} }
        post   :fetch_commits,          path: "release_notes/:note_id/fetch_commits"
        post   :submit_for_review,      path: "release_notes/:note_id/submit_for_review"
        post   :approve_review,         path: "release_notes/:note_id/approve_review"
        post   :reject_review,          path: "release_notes/:note_id/reject_review"
      end

      resources :release_checklists, only: [ :show, :update ] do
        member do
          post :check_item
          post :uncheck_item
          post :reset
          post :add_custom_item
          delete :remove_custom_item
        end
      end
    end
    resources :keywords, only: [ :index, :show ] do
      member do
        patch :append
      end
      collection do
        get :suggestions
        post :competitor_lookup
      end
    end
    resources :reviews, only: [ :index ] do
      member do
        post :reply
        delete :delete_reply
      end
      collection do
        post :sync
      end
    end
    resources :review_response_templates, only: [ :create, :update, :destroy ]
    resources :analytics, only: [ :index ] do
      collection do
        post :sync
      end
    end
    resources :audit_events, only: [ :index ], path: "audit_logs"
    resources :permissions, only: [ :index ]
    resource :sso_configuration, only: [ :show, :new, :create, :edit, :update, :destroy ]
    # BYOK panel under Settings → Security (mysigner-21 sub-ticket 2.2).
    # Two endpoints: PATCH to save/clear the customer's CMK ARN, POST
    # /verify to dry-run the probes without persisting. Both gated by
    # OrganizationPolicy#manage_byok? (admin/owner AND the Team-tier `byok`
    # entitlement — see Pricing::Entitlements).
    patch "security/byok",        to: "byok_settings#update", as: :update_byok_settings
    post  "security/byok/verify", to: "byok_settings#verify", as: :verify_byok_settings
    resources :custom_product_pages, except: [ :edit ] do
      member do
        post :sync
        patch :update_localization
        patch :update_version
        post :add_keyword
        delete :remove_keyword
        get :fetch_screenshots
        post :upload_screenshots
        get :upload_status
        post :submit_for_review
      end
    end

    resources :screenshot_projects do
      resources :screenshot_scenes, only: [ :create, :update, :destroy ] do
        get :image, on: :member
        get :thumbnail, on: :member
        post :copy, on: :member
        post :reorder, on: :collection
        patch :bulk_update, on: :collection
      end
      member do
        get :editor
        post :apply_template
        post :upload_export
        post :start_store_upload
        get :upload_status
        get :current_store_screenshots
        get :background_image_file
        get "custom_sticker_images/:attachment_id", action: :custom_sticker_image, as: :custom_sticker_image
        post :upload_background_image
        delete :remove_background_image
        post :upload_custom_sticker_image
        delete :delete_custom_sticker_image
      end
    end
  end
  resources :organization_invitations, only: [ :destroy ]
  get "/invitations/accept", to: "organization_invitations#accept", as: :accept_organization_invitation

  namespace :api do
    namespace :v1 do
      get "/status", to: "status#show"

      # User-scoped endpoints (not restricted by token's org)
      namespace :user do
        get "organizations", to: "organizations#index"
      end

      resources :organizations, only: [ :index, :show ] do
        # Phase 0: GET /credentials was REMOVED (aggregate leak of ASC + GP
        # credentials). Replaced by narrow per-purpose endpoints below.
        get :status, on: :member
        post :sync_app_store_connect, on: :member
        post :sync_google_play, on: :member
        post :sync_all, on: :member
        get :sync_status_all, on: :member
        post :sync, to: "sync#create", on: :member
        get "sync/status", to: "organizations#sync_status", on: :member
        get "sync/google_play/status", to: "organizations#sync_status_google_play", on: :member
        post :validate, on: :member

        # Devices
        resources :devices, only: [ :index, :show, :create, :update ]

        # App Store Connect credentials
        resources :app_store_connect_credentials, only: [ :create ]

        # Profiles
        resources :profiles, only: [ :index, :show, :create, :destroy ] do
          get :match, on: :collection
          post :auto_create, on: :collection
          get :download, on: :member
        end

        # Certificates
        resources :certificates, only: [ :index, :show ] do
          get :download, on: :member
        end

        # Bundle IDs
        resources :bundle_ids, only: [ :index, :show, :create, :destroy ]

        # Merchant IDs
        resources :merchant_ids, only: [ :index, :show, :create, :destroy ]

        # App Groups
        resources :app_groups, only: [ :index, :show, :create, :destroy ]

        # App Store Releases (iOS CLI defaults)
        resources :app_store_releases, only: [ :index, :show, :create, :update ]

        # Android Releases (Android CLI defaults, mirrors app_store_releases)
        resources :android_releases, only: [ :index, :show, :create, :update, :destroy ]

        # Apple Apps (iOS)
        resources :apple_apps, only: [ :index, :show ] do
          get "bundle_id/:bundle_id", to: "apple_apps#show_by_bundle_id", on: :collection, format: false

          # App-level metadata (subtitle, name, privacy info via appInfoLocalizations)
          resource :app_info, only: [ :show, :update ], controller: "app_info"
        end

        # Builds
        resources :builds, only: [ :index, :show ]

        # App Store Versions
        resources :app_store_versions, only: [ :index, :show, :create, :update ] do
          post :build, to: "app_store_versions#attach_build", on: :member
          post :submit, on: :member
          post :phased_release, on: :member

          # Version Localizations (whats_new, marketing_url, promotional_text, support_url)
          resources :localizations, only: [ :index, :create, :update, :destroy ],
                    controller: "app_store_version_localizations"
        end

        # Android Apps
        resources :android_apps, only: [ :index, :show, :create ] do
          # Android Tracks (scoped by package name) as collection routes (must come before generic package route)
          get "package/*package_name/tracks", to: "android_tracks#index", on: :collection, format: false
          get "package/*package_name/tracks/:track", to: "android_tracks#show", on: :collection, format: false

          # Show by package name for convenience; use glob to allow dots and disable format parsing
          get "package/*package_name", to: "android_apps#show_by_package", on: :collection, format: false

          # Android Builds (nested under apps)
          resources :android_builds, only: [ :create ]
        end

        # Google Play Credentials
        resources :google_play_credentials, only: [ :index, :create, :destroy ] do
          post :activate, on: :member
          post :test, on: :member
        end

        # Google Play short-lived OAuth access token for CLI / uploader use
        post "credentials/google_play/access_token", to: "google_play_access_tokens#create"

        # mysigner-47: bulk credential purge for `mysigner logout --purge`.
        # Deletes every ASC / Google Play / Apple Ads / Android keystore row
        # owned by the organization. Per-row delete emits an audit event.
        delete "credentials", to: "credentials#destroy"

        # App Store Connect build upload orchestration (CLI uses these to push .ipa to ASC)
        resources :asc_build_uploads, path: "builds/asc_upload", only: %i[create show update]

        # Play Store Releases
        resources :play_store_releases, only: [ :index, :show, :create, :update ]

        # Android Keystores
        resources :android_keystores, only: [ :index, :create, :destroy ] do
          get :download, on: :member
          post :activate, on: :member
          post :link_to_app, on: :member
          post "secrets", to: "android_keystore_secrets#create", on: :member
        end

        # Screenshot Projects & Exports
        resources :screenshot_projects, only: [ :index, :show ] do
          resources :screenshot_exports, only: [ :index, :create ] do
            collection do
              get :download
              delete :destroy
            end
          end
        end

        # Screenshot Uploads
        resources :screenshot_uploads, only: [ :index, :show, :create ]
      end
    end
  end
end
