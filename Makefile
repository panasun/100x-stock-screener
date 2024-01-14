install:
	mix deps.get

iex:
	iex -S mix

fetch-stock:
	iex -S mix GuruFocusScrape.fetch_stock()

screen-stock:
	iex -S mix GuruFocusScrape.stock_screen()
