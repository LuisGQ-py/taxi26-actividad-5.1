defmodule TaxiBeWeb.TaxiAllocationJob do
  use GenServer

  @allocation_timeout 90_000
  @estimated_arrival_time "5 minutos"
  @drivers_to_contact 3

  def start_link(request, name) do
    GenServer.start_link(__MODULE__, request, name: name)
  end

  def init(request) do
    Process.send(self(), :contact_drivers, [:nosuspend])

    {:ok,
     %{
       request: request,
       contacted_drivers: [],
       pending_drivers: [],
       accepted_driver: nil,
       timer: nil,
       phase: :allocating
     }}
  end

  def handle_info(:contact_drivers, %{request: request} = state) do
    drivers =
      candidate_taxis()
      |> Enum.take(@drivers_to_contact)

    Enum.each(drivers, fn driver ->
      notify_driver(driver.nickname, %{
        msg: booking_message(request),
        bookingId: request["booking_id"]
      })
    end)

    timer = Process.send_after(self(), :allocation_timeout, @allocation_timeout)

    {:noreply,
     %{
       state
       | contacted_drivers: drivers,
         pending_drivers: Enum.map(drivers, & &1.nickname),
         timer: timer,
         phase: :allocating
     }}
  end

  def handle_info(:allocation_timeout, %{phase: :allocating} = state) do
    notify_customer(
      state.request,
      "No fue posible encontrar un taxi disponible para tu solicitud."
    )

    {:stop, :normal, %{state | phase: :failed, timer: nil}}
  end

  def handle_info(:allocation_timeout, state) do
    {:noreply, state}
  end

  def handle_cast({:process_accept, username}, %{phase: :allocating} = state) do
    if username in state.pending_drivers do
      cancel_timer(state.timer)

      notify_customer(
        state.request,
        "Tu taxi #{username} está en camino. Tiempo estimado de llegada: #{@estimated_arrival_time}."
      )

      notify_other_drivers(state.pending_drivers, username, %{
        msg: "El viaje ya fue aceptado por otro conductor.",
        bookingId: state.request["booking_id"]
      })

      {:stop,
       :normal,
       %{
         state
         | accepted_driver: username,
           phase: :accepted,
           timer: nil,
           pending_drivers: []
       }}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:process_accept, _username}, state) do
    {:noreply, state}
  end

  def handle_cast({:process_reject, username}, %{phase: :allocating} = state) do
    new_pending_drivers = List.delete(state.pending_drivers, username)

    if Enum.empty?(new_pending_drivers) do
      cancel_timer(state.timer)

      notify_customer(
        state.request,
        "No fue posible encontrar un taxi disponible para tu solicitud."
      )

      {:stop,
       :normal,
       %{
         state
         | phase: :failed,
           timer: nil,
           pending_drivers: []
       }}
    else
      {:noreply, %{state | pending_drivers: new_pending_drivers}}
    end
  end

  def handle_cast({:process_reject, _username}, state) do
    {:noreply, state}
  end

  def handle_cast(_message, state) do
    {:noreply, state}
  end

  defp booking_message(request) do
    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address
    } = request

    "Viaje de '#{pickup_address}' a '#{dropoff_address}'"
  end

  defp notify_driver(username, payload) do
    case :global.whereis_name({:driver_channel, username}) do
      :undefined ->
        :driver_not_connected

      pid ->
        send(pid, {:booking_request, payload})
    end
  end

  defp notify_customer(request, message) do
    %{"username" => username} = request

    case :global.whereis_name({:customer_channel, username}) do
      :undefined ->
        :customer_not_connected

      pid ->
        send(pid, {:booking_request, %{msg: message, bookingId: request["booking_id"]}})
    end
  end

  defp notify_other_drivers(pending_drivers, accepted_driver, payload) do
    pending_drivers
    |> Enum.reject(fn username -> username == accepted_driver end)
    |> Enum.each(fn username -> notify_driver(username, payload) end)
  end

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(timer) do
    Process.cancel_timer(timer)
    :ok
  end

  def candidate_taxis() do
    [
      %{nickname: "frodo", latitude: 19.0319783, longitude: -98.2349368},
      %{nickname: "pippin", latitude: 19.0092933, longitude: -98.2473716},
      %{nickname: "samwise", latitude: 19.0061167, longitude: -98.2697737}
    ]
  end
end
