# Runtime logging

Runtime logs are execution observation. They do not create lifecycle state or
prove that a named role executed.

Use stable key=value fields for diagnostic context. Where available, include:

- durable task identity;
- lifecycle, working-round, planning-attempt, and specialist-execution
  identity supplied by Pilot;
- the explicit role and Pilot grant identity;
- App Server/session/process identity as observation;
- outcome and concise failure reason; and
- workspace, changed-path, authorization, and commit facts for writer runs.

Do not use external metadata or model-supplied fields as Runtime authority.
Do not infer execution from a role name, expected sequence, packet,
or log line. Pilot retains the host evidence required to reconcile a role run.

Runtime logs may report retries, process exits, and session events. Those are
mechanical observations, not automatic lifecycle progression. Keep credential
and secret material out of logs and UI responses.
