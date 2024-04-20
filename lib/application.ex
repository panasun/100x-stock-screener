defmodule StockScrape.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      :poolboy.child_spec(DB,
        name: {:local, DB.Supervisor},
        worker_module: DB,
        size: 1,
        max_overflow: 0
      ),
      :poolboy.child_spec(GuruFocusScrape,
        name: {:local, GuruFocusScrape.Supervisor},
        worker_module: GuruFocusScrape,
        size: 20,
        max_overflow: 3
      )
    ]

    opts = [strategy: :one_for_one, name: StockScrape.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
