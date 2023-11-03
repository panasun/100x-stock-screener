defmodule DB do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil)
  end

  def pool(request) do
    :poolboy.transaction(DB.Supervisor, fn pid ->
      case request do
        {:call, message} -> GenServer.call(pid, message, 10_000)
        {:cast, message} -> GenServer.cast(pid, message)
        _ -> raise ArgumentError, :invalid_request_format
      end
    end)
  end

  def put(key, value) do
    pool({:cast, {:put, key, value}})
  end

  def get(key) do
    pool({:call, {:get, key}})
  end

  @impl true
  def init(data_dir) do
    CubDB.start_link(data_dir: "db/stock")
  end

  @impl true
  def handle_cast({:put, key, value}, db) do
    result = CubDB.put(db, key, value)
    {:noreply, db}
  end

  @impl true
  def handle_call({:get, key}, _, db) do
    result = CubDB.get(db, key)
    {:reply, result, db}
  end
end
