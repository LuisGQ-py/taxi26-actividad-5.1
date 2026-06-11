defmodule TaxiBeWeb.TaxiAllocationJob do
  use GenServer

  @driver_response_timeout 60_000
  @estimated_arrival_time "5 minutos"

  def start_link(request, name) do
    GenServer.start_link(__MODULE__, request, name: name)
  end

  def init(request) do
    Process.send(self(), :contact_next_driver, [:nosuspend])

    {:ok,
     %{
       request: request,
       candidates: candidate_taxis(),
       current_taxi: nil,
       timer: nil,
       phase: :allocating
     }}
  end

  def handle_info(:contact_next_driver, %{candidates: []} = state) do
    notify_customer(
      state.request,
      "No fue posible encontrar un taxi disponible para tu solicitud."
    )

    {:stop, :normal, state}
  end

  def handle_info(:contact_next_driver, %{candidates: [taxi | remaining_taxis]} = state) do
    forward_request_to_driver(state.request, taxi)

    timer =
      Process.send_after(
        self(),
        {:driver_timeout, taxi.nickname},
        @driver_response_timeout
      )

    {:noreply,
     %{
       state
       | candidates: remaining_taxis,
         current_taxi: taxi,
         timer: timer,
         phase: :waiting_driver_response
     }}
  end

  def handle_info(
        {:driver_timeout, taxi_nickname},
        %{current_taxi: %{nickname: taxi_nickname}, phase: :waiting_driver_response} = state
      ) do
    Process.send(self(), :contact_next_driver, [:nosuspend])

    {:noreply, %{state | current_taxi: nil, timer: nil}}
  end

  def handle_info({:driver_timeout, _taxi_nickname}, state) do
    {:noreply, state}
  end

  def handle_cast(
        {:process_accept, username},
        %{current_taxi: %{nickname: username}, phase: :waiting_driver_response} = state
      ) do
    cancel_timer(state.timer)

    notify_customer(
      state.request,
      "Tu taxi #{username} está en camino. Tiempo estimado de llegada: #{@estimated_arrival_time}."
    )

    {:stop, :normal, %{state | phase: :accepted, timer: nil}}
  end

  def handle_cast(
        {:process_reject, username},
        %{current_taxi: %{nickname: username}, phase: :waiting_driver_response} = state
      ) do
    cancel_timer(state.timer)
    Process.send(self(), :contact_next_driver, [:nosuspend])

    {:noreply, %{state | current_taxi: nil, timer: nil}}
  end

  def handle_cast(_message, state) do
    {:noreply, state}
  end

  defp forward_request_to_driver(request, taxi) do
    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address,
      "booking_id" => booking_id
    } = request

    TaxiBeWeb.Endpoint.broadcast(
      "driver:" <> taxi.nickname,
      "booking_request",
      %{
        msg: "Viaje de '#{pickup_address}' a '#{dropoff_address}'",
        bookingId: booking_id
      }
    )
  end

  defp notify_customer(request, message) do
    %{"username" => username} = request

    TaxiBeWeb.Endpoint.broadcast(
      "customer:" <> username,
      "booking_request",
      %{msg: message}
    )
  end

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(timer) do
    Process.cancel_timer(timer)
    :ok
  end

  def candidate_taxis() do
    [
      %{nickname: "frodo", latitude: 19.0319783, longitude: -98.2349368},
      %{nickname: "samwise", latitude: 19.0061167, longitude: -98.2697737},
      %{nickname: "pippin", latitude: 19.0092933, longitude: -98.2473716}
    ]
  end
end
