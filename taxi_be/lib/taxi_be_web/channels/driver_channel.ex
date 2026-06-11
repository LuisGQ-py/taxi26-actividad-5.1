defmodule TaxiBeWeb.DriverChannel do
  use TaxiBeWeb, :channel

  @impl true
  def join("driver:" <> username, _payload, socket) do
    register_channel({:driver_channel, username})

    {:ok, assign(socket, :username, username)}
  end

  @impl true
  def handle_info({:booking_request, payload}, socket) do
    IO.inspect(payload, label: "MENSAJE DIRECTO AL DRIVER")

    push(socket, "booking_request", %{
      msg: payload[:msg] || payload["msg"],
      bookingId: payload[:bookingId] || payload["bookingId"]
    })

    {:noreply, socket}
  end

  defp register_channel(name) do
    case :global.whereis_name(name) do
      :undefined -> :ok
      _pid -> :global.unregister_name(name)
    end

    :global.register_name(name, self())
  end
end
