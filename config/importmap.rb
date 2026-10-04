# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "@hotwired--turbo-rails.js" # @8.0.23
pin "@hotwired/turbo", to: "@hotwired--turbo.js" # @8.0.23
pin "@rails/actioncable/src", to: "@rails--actioncable--src.js" # @7.2.302
pin "blobatar", to: "blobatar.js" # blobatar 2.7.0, vendored from https://unpkg.com/blobatar@2.7.0/dist/blob.js (MIT)
pin "blobatar/internal", to: "blobatar-internal.js" # blobatar 2.7.0, vendored from https://unpkg.com/blobatar@2.7.0/dist/internal.js (MIT)
