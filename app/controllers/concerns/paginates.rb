# Shared 20-per-page slicing for long question lists.
module Paginates
  PER_PAGE = 20

  private
    # Returns one page of scope and records its state for shared/_pager.
    # key lets a page carry two independent lists (page, t_page).
    def paginate(scope, key: :page)
      count = scope.count
      pages = [ (count.to_f / PER_PAGE).ceil, 1 ].max
      number = params[key].to_i.clamp(1, pages)
      @pagers ||= {}
      @pagers[key] = { key: key, number: number, pages: pages, count: count }
      scope.offset((number - 1) * PER_PAGE).limit(PER_PAGE)
    end
end
