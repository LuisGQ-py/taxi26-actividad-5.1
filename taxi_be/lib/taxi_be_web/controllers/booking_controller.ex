defmodule TaxiBeWeb.BookingController do
  use TaxiBeWeb, :controller

  alias TaxiBeWeb.TaxiAllocationJob

  def create(conn, req) do
    booking_id = UUID.uuid1()

    TaxiAllocationJob.start_link(
      req |> Map.put("booking_id", booking_id),
      String.to_atom(booking_id)
    )

    conn
    |> put_resp_header("Location", "/api/bookings/" <> booking_id)
    |> put_status(:created)
    |> json(%{msg: "We are processing your request"})
  end

  def update(conn, %{"action" => "accept", "username" => username, "id" => id}) do
    send_to_job(id, {:process_accept, username})

    json(conn, %{msg: "We will process your acceptance"})
  end

  def update(conn, %{"action" => "reject", "username" => username, "id" => id}) do
    send_to_job(id, {:process_reject, username})

    json(conn, %{msg: "We will process your rejection"})
  end

  def update(conn, %{"action" => "cancel", "username" => username, "id" => _id}) do
    IO.inspect("'#{username}' is cancelling a booking request")

    json(conn, %{msg: "Cancelation is not implemented in version 1"})
  end

  defp send_to_job(id, message) do
    id
    |> String.to_atom()
    |> Process.whereis()
    |> case do
      nil -> :booking_process_not_found
      pid -> GenServer.cast(pid, message)
    end
  end
end
