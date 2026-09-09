  import { Controller } from "@hotwired/stimulus"
  import DataTable from 'datatables.net-dt'

  const FIRST_PAGE = 1
  const PAGE_PARAM = 'page'
  const PAGE_SIZE = 10

  // DataTables indexes pages from 0, the URL numbers them from 1.
  const toPageNumber = (index) => index + FIRST_PAGE
  const toPageIndex = (number) => number - FIRST_PAGE

  // Connects to data-controller="table-component"
  export default class extends Controller {
    static values = {
      sortcolumn: String,
      paging: Boolean,
      searching: Boolean,
      noinitsort: Boolean,
      searchPlaceholder: { type: String, default: 'Search' },
      serverSide: Boolean,
      ordering: Boolean,
      ajaxUrl: String,
      columns: Array,
      showAll: Boolean,
      search: String,
      page: Number
    }

    connect() {
      const table = this.element.querySelector('table')
      const defaultSortColumn = parseInt(this.sortcolumnValue, 10)

      if (this.sortcolumnValue || this.searchingValue || this.pagingValue || this.serverSideValue) {
      
        this.table = new DataTable(`#${table.id}`, {
          paging: this.pagingValue,
          pageLength: PAGE_SIZE,
          // Deep link entry point, e.g. /agents?page=14 opens on the 14th page.
          ...(this.hasPageValue && { displayStart: toPageIndex(this.pageValue) * PAGE_SIZE }),
          ...(this.columnsValue?.length > 0 && { columns: this.columnsValue.map(name => ({ data: name })) }),
          info: false,
          lengthMenu: this.showAllValue ? [
            [10, 25, 50, 100, -1],
            [10, 25, 50, 100, 'All']
          ] : [
            [10, 25, 50, 100],
            [10, 25, 50, 100]
          ],
          ordering: this.orderingValue,
          searching: this.searchingValue,
          autoWidth: true,
          rowId: 'id',
          serverSide: this.serverSideValue,
          processing: true,
          ajax: this.serverSideValue ? {
            url: this.ajaxUrlValue,
            data: function (d) {
              return {
                page: Math.floor(d.start / d.length) + 1,
                pagesize: d.length,
                search: d.search.value 
              }
            },
            dataSrc: function (json) {
              return json.collection || []

            }
          } : null,
          order: this.noinitsortValue ? [] : [[defaultSortColumn, 'desc']],
          search: {
            return: true,
            // Primes the filter box so a deep link like /agents?search=inrae
            // lands pre-filtered. Server-side tables send it with the first
            // ajax call, so no extra request is made.
            search: this.searchValue
          },
          language: {
            search: '_INPUT_',
            searchPlaceholder: this.searchPlaceholderValue
          }
        })

        DataTable.ext.errMode = 'none';

        if (this.hasPageValue) {
          this.#trackPageInUrl()
        }
      }
      const searchInput = document.querySelector(`#${table.id}_filter input`)

      if (searchInput) {
        // Seeded so that clearing a short pre-filled search still resets the table.
        let lastSearchValue = this.searchValue || ''

        searchInput.addEventListener('input', () => {
          const value = searchInput.value
          // Check if the input value has changed and is at least 3 characters long
          if ((value.length >= 3) || (value.length === 0 && lastSearchValue.length !== 0)) {
            this.table.search(value).draw()
          }
        
          lastSearchValue = value
        })
      }

    }

    // Mirrors the current page back into the URL so it stays copy-pasteable,
    // which is also how a reader jumps ahead: edit ?page= in the address bar.
    #trackPageInUrl() {
      // A page number typed past the end returns no row: fall back to the last one.
      this.table.one('draw', () => {
        const { page, pages } = this.table.page.info()

        if (pages > 0 && page >= pages) {
          this.table.page(toPageIndex(pages)).draw('page')
        }
      })

      this.table.on('draw', () => {
        const number = toPageNumber(this.table.page.info().page)
        const url = new URL(window.location)

        if (number === FIRST_PAGE) {
          url.searchParams.delete(PAGE_PARAM)
        } else {
          url.searchParams.set(PAGE_PARAM, number)
        }

        window.history.replaceState({}, '', url)
      })
    }
  }
