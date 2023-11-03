defmodule GuruFocusScrape do
  alias DB

  def headers do
    [
      {"User-Agent",
       "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"}
    ]
  end

  def fetch_stock() do
    fetch_stock("KNSL")
  end

  def fetch_stock(quote) do
    result =
      "https://www.gurufocus.com/stock/#{quote}/summary"
      |> HTTPoison.get!(headers)
      |> (& &1.body).()
      |> IO.inspect()

    DB.put({:stock, quote, :summary_html}, result)
  end

  def get_stock(quote) do
    result = DB.get({:stock, quote, :summary_html}) |> IO.inspect()
  end
end
