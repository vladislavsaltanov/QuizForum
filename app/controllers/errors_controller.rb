# Public error pages in site style; skips auth so guests see them too.
class ErrorsController < ApplicationController
  allow_unauthenticated_access only: :not_found

  def not_found
    render status: :not_found
  end
end
