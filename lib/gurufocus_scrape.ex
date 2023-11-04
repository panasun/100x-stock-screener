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

  def parse_number(number) do
    s =
      number
      |> String.replace(",", "")

    case Float.parse(s) do
      {n, ""} -> n
      _ -> number
    end
  end

  def stock_screen() do
    ticker = "AAPL"
    stock = get_stock(ticker)

    data =
      %{
        "ticker" => ticker,
        "3_year_revenue_growth_rate" => stock["3_year_revenue_growth_rate"],
        "3_year_fcf_growth_rate" => stock["3_year_fcf_growth_rate"],
        "future_3_5y_total_revenue_growth_rate" => stock["future_3_5y_total_revenue_growth_rate"],
        "gross_margin" => stock["gross_margin"],
        "net_margin" => stock["net_margin"],
        "fcf_margin" => stock["fcf_margin"],
        "roe" => stock["roe"],
        "roa" => stock["roa"],
        "roic" => stock["roic"],
        "years_of_profitability_over_past_10_year" =>
          stock["years_of_profitability_over_past_10_year"],
        "pe_ratio" => stock["pe_ratio"],
        "forward_pe_ratio" => stock["forward_pe_ratio"],
        "peg_ratio" => stock["peg_ratio"],
        "ps_ratio" => stock["ps_ratio"],
        "price_to_free_cash_flow" => stock["price_to_free_cash_flow"],
        "price_to_operating_cash_flow" => stock["price_to_operating_cash_flow"],
        "ev_to_revenue" => stock["ev_to_revenue"],
        "ev_to_fcf" => stock["ev_to_fcf"],
        "ev_to_ebitda" => stock["ev_to_ebitda"],
        "revenue_ttm_mil" => stock["revenue_ttm_mil"],
        "cash_to_debt" => stock["cash_to_debt"],
        "debt_to_equity" => stock["debt_to_equity"]
      }
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        value = parse_number(value)

        Map.update(acc, key, value, fn value -> value end)
      end)

    Map.merge(data, %{
      "rule_of_40" => data["net_margin"] + data["3_year_revenue_growth_rate"],
      "exp_return_ps_3_year_revenue_growth" =>
        ((data["net_margin"] / 100 * 1 * (1 + data["3_year_revenue_growth_rate"] / 100) /
            data["ps_ratio"] +
            data["3_year_revenue_growth_rate"] / 100) * 100)
        |> Float.ceil(2),
      "exp_return_ps_3_year_fcf_growth" =>
        ((data["net_margin"] / 100 * 1 * (1 + data["3_year_fcf_growth_rate"] / 100) /
            data["ps_ratio"] +
            data["3_year_fcf_growth_rate"] / 100) * 100)
        |> Float.ceil(2),
      "exp_return_ps_future_3_5_year_revenue_growth" =>
        ((data["net_margin"] / 100 * 1 * (1 + data["future_3_5y_total_revenue_growth_rate"] / 100) /
            data["ps_ratio"] +
            data["future_3_5y_total_revenue_growth_rate"] / 100) * 100)
        |> Float.ceil(2)
    })
  end
end
