defmodule TaxiBeWeb.TaxiAllocationJob do
  use GenServer

  @allocation_timeout 90_000

  # Tiempos reales de la actividad:
  # taxi llega en 5 minutos y la penalización aplica si faltan 3 minutos o menos.
  @estimated_arrival_seconds 300
  @penalty_threshold_seconds 180
  @penalty_amount 20
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
       allocation_timer: nil,
       penalty_timer: nil,
       arrival_timer: nil,
       penalty_window: false,
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

    allocation_timer = Process.send_after(self(), :allocation_timeout, @allocation_timeout)

    {:noreply,
     %{
       state
       | contacted_drivers: drivers,
         pending_drivers: Enum.map(drivers, & &1.nickname),
         allocation_timer: allocation_timer,
         phase: :allocating
     }}
  end

  def handle_info(:allocation_timeout, %{phase: :allocating} = state) do
    notify_customer(
      state.request,
      "No fue posible encontrar un taxi disponible para tu solicitud."
    )

    notify_drivers(state.pending_drivers, %{
      msg: "La solicitud expiró porque ningún conductor aceptó a tiempo.",
      bookingId: state.request["booking_id"],
      closed: true
    })

    {:stop, :normal, %{state | phase: :failed, allocation_timer: nil}}
  end

  def handle_info(:allocation_timeout, state) do
    {:noreply, state}
  end

  def handle_info(:penalty_window_started, %{phase: :accepted} = state) do
    IO.puts("La reservación entró en ventana de penalización.")

    {:noreply, %{state | penalty_window: true, penalty_timer: nil}}
  end

  def handle_info(:penalty_window_started, state) do
    {:noreply, state}
  end

  def handle_info(:taxi_arrived, %{phase: :accepted} = state) do
    notify_customer(
      state.request,
      "Tu taxi #{state.accepted_driver} ha llegado al punto de recolección."
    )

    {:stop, :normal, %{state | phase: :arrived, arrival_timer: nil}}
  end

  def handle_info(:taxi_arrived, state) do
    {:noreply, state}
  end

  def handle_info({:penalty_countdown, 0}, state) do
    IO.puts("Ya inició la ventana de penalización. Si el cliente cancela ahora, se cobra $#{@penalty_amount}.")

    {:noreply, state}
  end

  def handle_info({:penalty_countdown, seconds}, state) when seconds > 0 do
    IO.puts("Faltan #{seconds} segundos para que inicie la ventana de penalización.")

    Process.send_after(self(), {:penalty_countdown, seconds - 1}, 1000)

    {:noreply, state}
  end

  def handle_cast({:process_accept, username}, %{phase: :allocating} = state) do
    if username in state.pending_drivers do
      cancel_timer(state.allocation_timer)

      notify_customer(
        state.request,
        "Tu taxi #{username} está en camino. Tiempo estimado de llegada: #{div(@estimated_arrival_seconds, 60)} minutos."
      )

      notify_other_drivers(state.pending_drivers, username, %{
        msg: "El viaje ya fue aceptado por otro conductor.",
        bookingId: state.request["booking_id"],
        closed: true
      })

      penalty_delay =
        max((@estimated_arrival_seconds - @penalty_threshold_seconds) * 1000, 0)

      penalty_timer =
        if penalty_delay == 0 do
          Process.send(self(), :penalty_window_started, [:nosuspend])
          nil
        else
          Process.send_after(self(), :penalty_window_started, penalty_delay)
        end

      arrival_timer =
        Process.send_after(self(), :taxi_arrived, @estimated_arrival_seconds * 1000)

      start_penalty_countdown(penalty_delay)

      {:noreply,
       %{
         state
         | accepted_driver: username,
           phase: :accepted,
           allocation_timer: nil,
           penalty_timer: penalty_timer,
           arrival_timer: arrival_timer,
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
      cancel_timer(state.allocation_timer)

      notify_customer(
        state.request,
        "No fue posible encontrar un taxi disponible para tu solicitud."
      )

      {:stop,
       :normal,
       %{
         state
         | phase: :failed,
           allocation_timer: nil,
           pending_drivers: []
       }}
    else
      {:noreply, %{state | pending_drivers: new_pending_drivers}}
    end
  end

  def handle_cast({:process_reject, _username}, state) do
    {:noreply, state}
  end

  def handle_cast({:process_cancel, _username}, %{phase: :allocating} = state) do
    cancel_timer(state.allocation_timer)

    notify_drivers(state.pending_drivers, %{
      msg: "El cliente canceló la solicitud antes de que fuera aceptada.",
      bookingId: state.request["booking_id"],
      closed: true
    })

    notify_customer(
      state.request,
      "Cancelaste la solicitud antes de que un conductor aceptara. No se aplicó ningún cargo."
    )

    {:stop, :normal, %{state | phase: :cancelled}}
  end

  def handle_cast({:process_cancel, _username}, %{phase: :accepted} = state) do
    cancel_timer(state.penalty_timer)
    cancel_timer(state.arrival_timer)

    charge =
      if state.penalty_window do
        @penalty_amount
      else
        0
      end

    notify_driver(state.accepted_driver, %{
      msg: "El cliente canceló el viaje.",
      bookingId: state.request["booking_id"],
      closed: true
    })

    customer_message =
      if charge > 0 do
        "Cancelaste el viaje dentro de los últimos 3 minutos antes de la llegada. Se aplicó un cargo de $#{charge}."
      else
        "Cancelaste el viaje antes de la ventana de penalización. No se aplicó ningún cargo."
      end

    notify_customer(state.request, customer_message)

    {:stop, :normal, %{state | phase: :cancelled}}
  end

  def handle_cast({:process_cancel, _username}, state) do
    {:noreply, state}
  end

  def handle_cast(_message, state) do
    {:noreply, state}
  end

  defp start_penalty_countdown(milliseconds) do
    seconds = div(milliseconds, 1000)
    Process.send(self(), {:penalty_countdown, seconds}, [:nosuspend])
  end

  defp booking_message(request) do
    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address
    } = request

    "Viaje de '#{pickup_address}' a '#{dropoff_address}'"
  end

  defp notify_driver(nil, _payload), do: :driver_not_found

  defp notify_driver(username, payload) do
    case :global.whereis_name({:driver_channel, username}) do
      :undefined ->
        :driver_not_connected

      pid ->
        send(pid, {:booking_request, payload})
    end
  end

  defp notify_drivers(usernames, payload) do
    Enum.each(usernames, fn username ->
      notify_driver(username, payload)
    end)
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
