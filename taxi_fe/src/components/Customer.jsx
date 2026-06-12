import React, { useEffect, useState } from 'react';
import Button from '@mui/material/Button';
import socket from '../services/taxi_socket';
import { TextField } from '@mui/material';

function Customer(props) {
  const [pickupAddress, setPickupAddress] = useState(
    "Tecnologico de Monterrey, campus Puebla, Mexico"
  );
  const [dropOffAddress, setDropOffAddress] = useState(
    "Triangulo Las Animas, Puebla, Mexico"
  );
  const [msg, setMsg] = useState("");
  const [msg1, setMsg1] = useState("");
  const [bookingId, setBookingId] = useState(null);

  useEffect(() => {
    const channel = socket.channel("customer:" + props.username, { token: "123" });

    channel.on("booking_request", dataFromPush => {
      console.log("Received customer event", dataFromPush);
      setMsg1(dataFromPush.msg);

      if (dataFromPush.bookingId) {
        setBookingId(dataFromPush.bookingId);
      }
    });

    channel
      .join()
      .receive("ok", () => console.log("Joined customer channel:", props.username))
      .receive("error", resp => console.log("Unable to join customer channel", resp));
  }, [props.username]);

  const submit = () => {
    fetch(`http://localhost:4000/api/bookings`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        pickup_address: pickupAddress,
        dropoff_address: dropOffAddress,
        username: props.username
      })
    })
      .then(resp => resp.json())
      .then(dataFromPOST => {
        setMsg(dataFromPOST.msg);
        setMsg1("");
        setBookingId(dataFromPOST.bookingId);
      });
  };

  const cancel = () => {
    if (!bookingId) {
      setMsg1("No hay una reservación activa para cancelar.");
      return;
    }

    fetch(`http://localhost:4000/api/bookings/${bookingId}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        action: "cancel",
        username: props.username
      })
    })
      .then(resp => resp.json())
      .then(dataFromPOST => {
        setMsg(dataFromPOST.msg);
      });
  };

  return (
    <div style={{ textAlign: "center", borderStyle: "solid" }}>
      Customer: {props.username}

      <TextField
        fullWidth
        label="Pickup address"
        onChange={ev => setPickupAddress(ev.target.value)}
        value={pickupAddress}
      />

      <TextField
        fullWidth
        label="Drop off address"
        onChange={ev => setDropOffAddress(ev.target.value)}
        value={dropOffAddress}
      />

      <div style={{ margin: "10px" }}>
        <Button onClick={submit} variant="outlined" color="primary">
          Submit
        </Button>

        <Button
          onClick={cancel}
          variant="outlined"
          color="secondary"
          disabled={!bookingId}
          style={{ marginLeft: "10px" }}
        >
          Cancel
        </Button>
      </div>

      <div style={{ backgroundColor: "lightcyan", minHeight: "40px" }}>
        {msg}
      </div>

      <div style={{ backgroundColor: "lightblue", minHeight: "40px" }}>
        {msg1}
      </div>
    </div>
  );
}

export default Customer;