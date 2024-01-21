install:
	mix deps.get

iex:
	iex -S mix

fetch-stock:
	iex -S mix GuruFocusScrape.fetch_stock()

parse-summary-data:
	iex -S mix GuruFocusScrape.parse_summary_data()

screen-stock:
	iex -S mix GuruFocusScrape.stock_screen()
