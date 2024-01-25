defmodule GuruFocusScrape do
  require Elixlsx
  alias Elixlsx.{Workbook, Sheet}
  alias DB

  # 1. fetch_stock
  # 2. parse_summary_data
  # 3. stock_screen

  def file_name do
    "bom_stock"
  end

  def headers do
    [
      {"User-Agent",
       "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"}
    ]
  end

  def get_tickers() do
    case File.read("priv/#{file_name}.txt") do
      {:ok, content} ->
        tickers = String.split(content, ~r/\r?\n/)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_stock() do
    get_tickers()
    # |> Enum.drop(792)
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
    case number do
      nil ->
        0

      _ ->
        s =
          number
          |> String.replace(",", "")

        case Float.parse(s) do
          {n, ""} -> n
          _ -> number
        end
    end
  end

  def stock_screen() do
    data =
      get_tickers()
      |> Enum.map(fn ticker ->
        stock_screen(ticker)
      end)

    data |> write_to_csv()
    data
  end

  def ps_valuation(growth_rate, net_margin, ps_ratio) do
    case ps_ratio do
      0 ->
        0

      _ ->
        ((net_margin / 100 * 1 * (1 + growth_rate / 100) /
            ps_ratio +
            growth_rate / 100) * 100)
        |> Float.ceil(2)
    end
  end

  def stock_screen(ticker) do
    stock = get_stock(ticker)
    IO.inspect("stock_screen: #{ticker}")

    data =
      %{
        "0_ticker" => ticker,
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
        "debt_to_equity" => stock["debt_to_equity"],
        "beneish_m_score" => stock["beneish_m_score"]
      }
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        value = parse_number(value) || 0

        Map.update(acc, key, value, fn value -> value end)
      end)

    valuation = %{
      "rule_of_40" => data["net_margin"] + data["3_year_revenue_growth_rate"],
      "rule_of_40_fcf" => data["fcf_margin"] + data["3_year_revenue_growth_rate"],
      # |> Float.ceil(2),
      "exp_return_ps_3_year_revenue_growth_net_margin" =>
        ps_valuation(data["3_year_revenue_growth_rate"], data["net_margin"], data["ps_ratio"]),
      "exp_return_ps_3_year_fcf_growth_net_margin" =>
        ps_valuation(data["3_year_fcf_growth_rate"], data["net_margin"], data["ps_ratio"]),
      "exp_return_ps_future_3_5_year_revenue_growth_net_margin" =>
        ps_valuation(
          data["future_3_5y_total_revenue_growth_rate"],
          data["net_margin"],
          data["ps_ratio"]
        ),
      "exp_return_ps_3_year_revenue_growth_fcf_margin" =>
        ps_valuation(data["3_year_revenue_growth_rate"], data["fcf_margin"], data["ps_ratio"]),
      "exp_return_ps_3_year_fcf_growth_fcf_margin" =>
        ps_valuation(data["3_year_fcf_growth_rate"], data["fcf_margin"], data["ps_ratio"]),
      "exp_return_ps_future_3_5_year_revenue_growth_fcf_margin" =>
        ps_valuation(
          data["future_3_5y_total_revenue_growth_rate"],
          data["fcf_margin"],
          data["ps_ratio"]
        )
    }

    Map.merge(data, valuation)
  end

  def write_to_csv(data) do
    headers =
      data
      |> Enum.at(0)
      |> Enum.map(fn {key, value} -> key end)

    sheet =
      %Sheet{
        name: "Data",
        rows: [
          headers
          | Enum.map(data, fn r ->
              Enum.map(headers, fn c ->
                Map.get(r, c)
              end)
            end)
        ],
        row_heights: %{4 => 60}
      }
      |> IO.inspect()

    workbook = %Workbook{sheets: [sheet]}

    Workbook.append_sheet(%Workbook{}, sheet)
    |> Elixlsx.write_to("data_#{file_name}.xlsx")
  end
end
