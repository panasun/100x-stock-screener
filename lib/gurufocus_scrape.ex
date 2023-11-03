defmodule GuruFocusScrape do
  # alias CubDB

  def headers do
    [
      {"User-Agent",
       "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"}
    ]
  end

  def fetch_stock() do
    {:ok, db} = CubDB.start_link(data_dir: "db/stock")
    fetch_stock(db, "KNSL")
  end

  def fetch_stock(db, quote) do
    result =
      "https://www.gurufocus.com/stock/#{quote}/summary"
      |> HTTPoison.get!(headers)
      |> (& &1.body).()
      |> IO.inspect()

    :ok = CubDB.put(db, {:stock, quote}, %{summary_html: result})
  end
end
