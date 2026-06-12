import React, { useEffect, useState } from 'react';
import Button from '@mui/material/Button';

import socket from '../services/taxi_socket';
import { Card, CardContent, Typography } from '@mui/material';

function Driver(props) {
  const [message, setMessage] = useState();
  const [bookingId, setBookingId] = useState();
  const [visible, setVisible] = useState(false);
  const [closed, setClosed] = useState(false);

  useEffect(() => {
    const channel = socket.channel("driver:" + props.username, { token: "123" });

    channel.on("booking_request", data => {
      console.log("Received driver event", props.username, data);
      setMessage(data.msg);
      setBookingId(data.bookingId);
      setClosed(data.closed === true);
      setVisible(true);
    });

    channel
      .join()
      .receive("ok", () => console.log("Joined driver channel:", props.username))
      .receive("error", resp => console.log("Unable to join driver channel", resp));
  }, [props.username]);

  const reply = decision => {
    fetch(`http://localhost:4000/api/bookings/${bookingId}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: decision, username: props.username })
    }).then(() => setVisible(false));
  };

  return (
    <div style={{ textAlign: "center", borderStyle: "solid" }}>
      Driver: {props.username}
      <div style={{ backgroundColor: "lavender", height: "120px" }}>
        {
          visible ?
            <Card variant="outlined" style={{ margin: "auto", width: "600px" }}>
              <CardContent>
                <Typography>
                  {message}
                </Typography>
              </CardContent>

              {
                !closed ?
                  <>
                    <Button onClick={() => reply("accept")} variant="outlined" color="primary">
                      Accept
                    </Button>
                    <Button onClick={() => reply("reject")} variant="outlined" color="secondary">
                      Reject
                    </Button>
                  </> :
                  null
              }
            </Card> :
            null
        }
      </div>
    </div>
  );
}

export default Driver;