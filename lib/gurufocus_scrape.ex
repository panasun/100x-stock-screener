defmodule GuruFocusScrape do
  alias DB

  def headers do
    [
      {"User-Agent",
       "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"}
    ]
  end

  def get_tickers() do
    case File.read("priv/us_stock.txt") do
      {:ok, content} ->
        tickers = String.split(content, ~r/\r?\n/)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_stock() do
    get_tickers()
    |> Enum.drop(5034)
    |> Enum.map(fn ticker ->
      IO.inspect("fetch_stock: #{ticker}")

      fetch_stock(ticker)
    end)
  end

  def fetch_stock(ticker) do
    ticker = String.trim(ticker)

    result =
      "https://www.gurufocus.com/stock/#{ticker}/summary"
      |> HTTPoison.get!(headers, timeout: 20_000)
      |> (& &1.body).()

    DB.put({:stock, ticker, :summary_html}, result)
  end

  def get_stock(ticker) do
    result = DB.get({:stock, ticker, :summary_html}) |> IO.inspect()
  end
end
