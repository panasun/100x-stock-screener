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

  def get_stock_summary_html(ticker) do
    DB.get({:stock, ticker, :summary_html})
  end

  def get_stock(ticker) do
    DB.get({:stock, ticker, :summary})
  end

  def clean_title(title) do
    title
    |> String.replace("\n", "")
    |> String.replace("-", "_")
    |> String.replace("(", " ")
    |> String.replace(")", "")
    |> String.replace("%", "")
    |> String.replace("$", "")
    |> String.replace("  ", " ")
    |> String.trim()
    |> String.replace(" ", "_")
    |> String.downcase()
  end

  def parse_summary_data() do
    get_tickers()
    |> Enum.map(fn ticker ->
      IO.inspect("parse_summary_data: #{ticker}")

      parse_summary_data(ticker)
    end)
  end

  def parse_summary_data(ticker) do
    html = get_stock_summary_html(ticker)
    {:ok, document} = Floki.parse_document(html)

    data1 =
      document
      |> Floki.find(".stock-indicators-table-row")
      |> Enum.map(fn tr_element ->
        td_elements = Floki.find(tr_element, "td")

        key =
          td_elements
          |> Enum.at(1)
          |> Floki.text()
          |> clean_title()

        value =
          td_elements
          |> Enum.at(2)
          |> Floki.text()
          |> String.trim()

        {key, value}
      end)

    data2 =
      document
      |> Floki.find(".t-caption")
      |> Enum.map(fn tr_element ->
        td_elements = Floki.find(tr_element, "td")

        key =
          td_elements
          |> Enum.at(1)
          |> Floki.text()
          |> clean_title()

        value =
          td_elements
          |> Enum.at(2)
          |> Floki.text()
          |> String.trim()

        {key, value}
      end)
      |> Enum.filter(fn {key, value} ->
        key != nil and key != ""
      end)

    data =
      ([{"ticker", ticker}] ++ data1 ++ data2)
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        Map.update(acc, key, value, fn current_value ->
          current_value
        end)
      end)

    DB.put({:stock, ticker, :summary}, data)

    data
  end
end
