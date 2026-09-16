**Requirements Analysis and Specification Document**

# **1| Introduction**

### **1.1. Scope**

Race Manager supports the preparation, supervision, and review of kart racing events. Drivers register individually or as part of a team, submit event waivers, consult their participation status, and review race information. Race directors organize events and manage race operations. Administrators manage accounts, shared configuration, signed documents, and official result imports. Viewers follow live timing.

The system boundary includes the mobile application and its backend service. Physical karts, timing transponders, trackside personnel, third-party timing platforms, and any external payment process remain outside that boundary. Race Manager observes externally supplied timing information; it does not measure lap times directly or physically enforce flags and penalties. The initial scope includes:

- Accounts, authentication, and differentiated access.
- Circuit and event information, individual and team registrations, and waiting lists.
- Event waiver submission and administrative document retrieval.
- Live timing, kart assignments, stint tracking, race control messages, and penalties.
- In-app notifications, official results, and available performance summaries.

Payment processing, mobile push delivery, Android and web clients, complete offline operation, and advanced telemetry analysis are future extensions. Recording a registration cost or a `pending_payment` status does not imply that the application processes payments. Adding teammates by email does not imply an implemented email delivery or invitation acceptance service.

#### **1.1.1. World phenomena**

| **ID** | **Phenomenon outside the software boundary**     |
| ------------ | ------------------------------------------------------ |
| W1           | Drivers and teams participate in a physical kart race. |
| W2           | Karts complete laps and cross timing detection points. |

**1|**

2

| W3 | Drivers enter the pits and change drivers during endurance races.                                         |
| -- | --------------------------------------------------------------------------------------------------------- |
| W4 | Race officials decide when to start, interrupt, resume, or stop a session and whetherto impose penalties. |
| W5 | Organizers check participation conditions and any payments outside the application.                       |
| W6 | A participant reads and agrees to the conditions of an event waiver.                                      |

#### **1.1.2. Shared phenomena**

| **ID** | **Controller** | **Phenomenon visible across the system****boundary**                                                      |
| ------------ | -------------------- | --------------------------------------------------------------------------------------------------------------------- |
| S1           | World                | A person submits account details andauthentication credentials.                                                       |
| S2           | World                | A participant submits or changes an individualor team registration.                                                   |
| S3           | World                | An official submits event settings, registrationdecisions, kart assignments, pit changes,penalties, or race commands. |
| S4           | World                | A participant submits personal details and adrawn signature for an event waiver.                                      |
| S5           | World                | A timing provider exposes standings and laptiming data.                                                               |
| S6           | World                | An administrator supplies an official results fileor changes shared configuration.                                    |
| S7           | Machine              | The application displays event details,participation status, and operation outcomes.                                  |
| S8           | Machine              | The application displays timing updates, stintinformation, messages, and penalties.                                   |
| S9           | Machine              | The application makes notifications and signedwaiver documents available to authorized users.                         |
| S10          | Machine              | The application presents published results andavailable performance summaries.                                        |

Internal phenomena include validating requests, maintaining records, calculating stint durations, normalizing provider data, and distributing updates to the correct subscribers.

**1|**

3

### **1.2. Purpose**

This document provides a common reference for implementation work and acceptance activities. Goals describe the expected outcomes; requirements describe observable software obligations; domain assumptions identify conditions outside the software’s control.

| **Goal** | **Intended outcome**                                                                              | **Relevant phenomena**   |
| -------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------ |
| G1             | Participants can prepare for an eventand understand their eligibility andregistration status.           | W1, W5, W6, S1, S2, S4, S7, S9 |
| G2             | Team representatives can organizeteam participation and follow teamperformance.                         | W1, W3, S2, S3, S7, S8         |
| G3             | Viewers and participants can followcurrent race progress.                                               | W2, S5, S8                     |
| G4             | Race directors can coordinate eventand race operations using consistentinformation.                     | W3, W4, S3, S5, S7, S8         |
| G5             | Administrators can maintain accounts,permissions, circuits, and eventdocuments.                         | S1, S4, S6, S9                 |
| G6             | Participants can consult publishedresults and review availableperformance data.                         | W2, S5, S6, S10                |
| G7             | Users receive understandable feedbackand appropriately restricted accessthroughout the event lifecycle. | S1–S10                        |

### **1.3. Definitions, Acronyms, and Abbreviations**

| **Term** | **Definition**                                                                      |
| -------------- | ----------------------------------------------------------------------------------------- |
| RASD           | Requirements Analysis and Specification Document.                                         |
| Actor          | A person or external system interacting with Race Manager.                                |
| Event          | An organized kart racing activity with a schedule, participation rules,and registrations. |

**1|**

4

Session A named on-track activity within an event, such as qualifying or a race.

| Registration                | The association between a participant and an event, optionallyincluding team membership.                                      |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Team representative /leader | The participant responsible for a team’s registration; not a separateglobal permission role.                                 |
| Stint                       | An interval of on-track driving tracked for an assigned kart, excludingpauses and pit time according to the rules below.      |
| Waiver / release form       | Event conditions and participant information submitted with a drawnsignature.                                                 |
| Official result             | A result published through an authorized administrative operation.                                                            |
| Live timing                 | Continuously refreshed information obtained from an external timingsource; not necessarily the final official classification. |
| API / REST                  | Application Programming Interface / Representational State Transfer.                                                          |
| JSON                        | Javascript Object Notation used for internal data exchange.                                                                   |
| JWT                         | JSON Web Token used for authenticated access.                                                                                 |
| HTTPS / WSS                 | Encrypted HTTP / encrypted WebSocket communication.                                                                           |
| CSV / PDF                   | Comma-separated values / Portable Document Format.                                                                            |
| UML                         | Unified Modeling Language.                                                                                                    |
| Alloy                       | A language and analyzer for bounded relational modeling.                                                                      |
| TBD                         | To be decided or confirmed by the project stakeholders.                                                                       |

Identifiers `R` , `P` , and `Q` denote functional, performance, and quality requirements. “Shall” expresses a specification obligation. A requirement is not a claim of existing implementation.

### **1.4. Document Structure**

- **Section 2** describes actors, domain concepts, lifecycle rules, and assumptions.
- **Section 3** defines scenarios, use cases, interface requirements, functional requirements, quality requirements, and traceability.

5

# **2| Overall Description**

### **2.1. Product Perspective**

Race Manager combines a native iOS client with a backend that maintains event records and retrieves timing information from supported providers, such as ApexTiming and RaceFacer. Users interact through role-appropriate screens. Several users may follow the same timing source, while others follow a different source.

Production access uses a configured remote service. Local discovery supports development use. Neither network discovery nor access to a timing page grants administrative privileges.

#### **2.1.1. Domain model**

| **Concept** | **Relevant information and relationships**                                                                                   |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| User              | Identity, credentials, profile, and one global role; may haveregistrations in multiple events.                                     |
| Circuit           | Track information and a supported timing source; may host multipleevents.                                                          |
| Event             | Schedule, circuit/location, registration limits, team-size limits, waivertext, event status, and operational session status.       |
| Registration      | Belongs to one event and identifies a participant by an account or apending email association; belongs to one event-specific team. |
| Team              | Conceptual grouping of registrations within one event, with a leaderand a name.                                                    |
| Signed waiver     | Associates a participant with an event and the submitted personalinformation and signature.                                        |
| Kart assignment   | Associates a kart number within an event with an individual entry orteam.                                                          |
| Penalty           | Refers to an event and kart, with type, optional time value, note, andtimestamp.                                                   |

**2|**

6

| Race message          | Refers to an event and optionally a particular kart; includes type, text,and timestamp.                           |
| --------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Timing snapshot / lap | Provider-derived information associated with a source session and,where available, an event and kart.             |
| Result                | Event classification data, optional participant/team association, timingvalues, and official standings indicator. |
| Notification          | A message belonging to a recipient, optionally linked to an event, withread status.                               |

<!-- Start of picture text -->

TrackRaceS i gnal-  name: Str i ng-  type: Str i ng -  locat i on: Str i ng-  rec i p i ent: Integer -  off i c i alWebs i te: Str i ng-  text: Str i ng -  c i rcu i tLayout: Str i ng-  t i me: DateT i me 0.*0.* hosts1.1Event-  number: Integer Lap 0.* 1.N Kart 1.N 0.* 1.* --  t dateAndT i tle: Str i ng i me: DateT i me-  lapT i me: Integer -  raceNumber: Integer 1.1 Stand i ngs -  type: Str i ng-  record i ngT i me: DateT i me -  raceDurat i on: Integer1.1 0.1 -  pos i t i on: Integer -  max i mumSt i ntDurat i on: Integer-  gap: Str i ng 1.1 -  max i mumNumberOfPart i c i pants: Integer-  lapsCompleted: Integer-  reg i strat i onFee: Dec i mal-  bestLap: Integer0.* -  m i n i mumNumberOfPart i c i pants: IntegerPenalty L i ab i l i tyWa i ver -  reg i strat i onDeadl i ne: DateT i me-  status: Str i ng-  type: Str i ng -  acceptedText: Str i ng-  seconds: Integer -  s i gnature: Str i ngSt i nt 0.* --  reason: Str t i me: DateT i ng i me -  s i gn i ngDateAndT i me: DateT i me0.1 0.* 1.1-  startT i me: DateT i me-  endT i me: DateT i me-  ballastAppl i ed: Dec i mal 0.10.* Team 0.1 1.* 0.*-  name: Str i ng Reg i strat i on 1.*0.* -  status: Str i ng- i sTeamLeader: Boolean0.*1.1 0.* Regs i trat i on Not i f i cat i onAdm i n User-  status: Str i ng 1.1-  f i rstName: Str i ng - i sTeamLeader: Boolean ResultBase User --  lastName: Str ema i l: Str i ng i ng 0.* -  f i nalPos i t i on: Integer-  dateOfB i rth: Date 0.* -  bestLap: Integer-  laps: IntegerRace D i rector -  taxCode: Str i ng - averageLap: Boolean-  res i dence: Str i ng-  declaredWe i ght: Dec i mal

Figure 2.1: UML domain class diagram

#### **2.1.2. Event and session lifecycle**

Event lifecycle and operational session state are separate. Finishing an event must not be confused with pausing a session or publishing results.

**2|**

7

| **Lifecycle** | **State** | **Meaning**                                             |
| ------------------- | --------------- | ------------------------------------------------------------- |
| Event               | `scheduled`   | The event is planned.                                         |
| Event               | `started`     | The event is underway and may containmultiple sessions.       |
| Event               | `finished`    | The event is closed; historical informationremains available. |
| Session             | `not_started` | No operational session has begun.                             |
| Session             | `running`     | Eligible on-track stint timers advance.                       |
| Session             | `paused`      | Timers are suspended and their elapsedvalues are preserved.   |
| Session             | `stopped`     | The session has ended.                                        |

The intended normal event progression is `scheduled` _→_ `started` _→_ `finished` . A scheduled event may also close through the expiration policy. An explicit start action initializes stint counters and starts the session. Yellow and blue flags can be signaled, a green flag clears their effects, and a checkered flag or a red flag stops it. A subsequent session requires an explicit new start.

###### **TEXTUAL PLACEHOLDER — FIGURE 2.3**

Insert two separate UML state diagrams using the states above. Label start, red flag, green flag, checkered flag, explicit new session, manual event closure, and expiration. Make clear that session commands do not independently imply publication of results.

Figure 2.2: Event and session state diagrams (placeholder)

#### **2.1.3. Registration lifecycle**

| **State**     | **Meaning**                                                             | **Intended transitions**                                       |
| ------------------- | ----------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `pending_payment` | Entry is awaiting organizerconfirmation, including anyexternal payment check. | Confirm to`confirmed`; move to `waitlist`;eligible cancellation. |
| `waitlist`        | Entry is awaiting admission.                                                  | Admit to`pending_payment`; eligiblecancellation.                   |
| `confirmed`       | Organizer has confirmed theentry.                                             | Organizer may return it to`pending_payment`or remove it.           |

**2|**

8

Late registrations and entries exceeding admission capacity enter the waiting list. An individual requesting participation in a team-format event without a team also enters the waiting list. Ordinary self-cancellation of a confirmed registration is blocked in the current workflow; leaving a team has a separate policy. Pending teammate account association is distinct from registration status. “Invited” and “rejected” are not baseline registration states.

###### **TEXTUAL PLACEHOLDER — FIGURE 2.4**

Show the three states above, initial routing based on deadline/capacity/team assignment, organizer confirmation and reversal, and cancellation/removal as terminal outcomes. Annotate the distinction between participant cancellation and organizer removal.

Figure 2.3: Registration state diagram (placeholder)

### **2.2. Product Functions**

| **Actor**      | **Principal functions**                                                                                               |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Visitor              | Access just live timing data from available circuits. Doesn’t requiresigning in and hasn’t access to other functions.     |
| Authenticated viewer | Create an account and sign in. Has access to events’ informations andcan register to them.                                 |
| Driver               | Maintain a profile, register, sign an event waiver, see their kart/teamand notifications, and consult results.              |
| Team representative  | Create and maintain the team’s entry, identify teammates, and followteam race information.                                 |
| Race director        | Manages all live event related actions, such as update pit status,control sessions, deliver messages and penalties.         |
| Administrator        | Perform inherited operational functions and manage user roles,circuits, waiver administration, and official result imports. |
| Timing provider      | Expose the externally measured timing information retrieved by RaceManager.                                                 |

Application roles are ordered `viewer < user < race_director < admin` . A team leader is identified within an event rather than through an additional global role. The baseline specification reserves participation functions for `user` or higher; consistent enforcement for `viewer` accounts requires review against current endpoints. The `admin` role grants the highest privileges and functionality, with additional capabilities not available to other accounts.

**2|**

9

### **2.3. User Characteristics**

Drivers and viewers may have little technical knowledge and use the application briefly in a busy trackside environment. They need readable information and explicit outcomes. Team representatives need to acquire timing and stint information quickly. Race directors need efficient controls and protection against accidental state changes. Administrators need searchable records and precise permission boundaries.

Users are expected to understand basic karting terms, while the interface should explain application-specific statuses such as waiting-list admission and pending confirmation.

### **2.4. Assumptions, Dependencies, and Constraints**

#### **2.4.1. Dependencies and constraints**

- The initial client is an iOS application.
- The existing implementation uses SwiftUI, FastAPI, SQLite, and browser-based provider adapters.
- Timing depends on reachable provider pages with interpretable data. Provider changes can require adapter maintenance.
- Remote use depends on network connectivity and the configured service endpoint; local discovery is a development facility.
- Waiver export requires PDF generation. Official result import currently requires an administrator-supplied CSV file.
- The application has no baseline integration with payment gateways, transponders, or physical flag equipment.

#### **2.4.2. Domain assumptions**

| **ID** | **Assumption**                                                                                                     |
| ------------ | ------------------------------------------------------------------------------------------------------------------------ |
| D1           | Organizers supply the correct schedule, participation rules, waiver text, and circuitinformation.                        |
| D2           | A provider’s timing values correspond to the selected physical session and areaccurate enough for the intended display. |
| D3           | Officials record kart assignments and pit activity correctly when these are notsupplied automatically.                   |
| D4           | Participants provide their own accurate personal details and sign their own eventwaiver.                                 |

**2|**

10

| D5 | Organizers verify any payment externally before confirming a registration wherepayment is required.               |
| -- | ----------------------------------------------------------------------------------------------------------------- |
| D6 | An administrator grants elevated roles only to people authorized by the organizer.                                |
| D7 | Devices and the backend have usable connectivity during live operation; disconnectionremains a handled exception. |
| D8 | The backend clock is sufficiently accurate for registration deadlines and elapsed-timecalculations.               |
| D9 | Officials remain responsible for physical race decisions and enforcement outside theapplication.                  |

11

# **3| Specific Requirements**

### **3.1. Scenarios Identification**

**SC1 — Preparing for an individual race.** User creates an account, finds a scheduled sprint race, and reads the cost and deadline. Her registration becomes pending confirmation. She reads and can sign the event waiver. After checking the external payment, the director confirms her registration, and User receives an in-app notification.

**SC2 — Organizing an endurance team.** User creates a team and supplies his teammates’ identifiers. The system validates membership and team size. Existing users see the relevant notifications; an unlinked email/username remains distinguishable from a registered account. User follows the team’s registration.

**SC3 — Joining a full event.** User requests entry after available capacity has been reached. The system places him on the waiting list. A director later admits him to pending confirmation and confirms him only after the necessary organizer checks.

**SC4 — Following a live timing with a feed interruption.** User selects a timing source and receives standings updates. When the provider or connection becomes unavailable, the application indicates the interruption. Following recovery, it displays fresh data for the selected source.

**SC5 — Controlling an interrupted endurance session.** Race Director starts a session, records pit entries, and sends a red flag. Active stint timers pause. A stopped session cannot resume through a green flag alone but has to be re-initiated.

**SC6 — Applying a stint penalty.** An assigned kart exceeds the configured stint limit. The backend records one automatic penalty for that stint, even if no mobile client is connected. A Race Director can review the penalty; deleting it does not cause the same stint to generate it repeatedly.

**SC7 — Publishing results.** An administrator imports a classification CSV. The system reports accepted rows and row-level problems. If every row is invalid, it preserves the previous classification. Participants can subsequently inspect the official results and available lap statistics.

**SC8 — Updating administrative access.** An administrator promotes a user to race director. Subsequent server-side authorization uses the current role. Only administrators can change other users’ privileges.

**3|**

12

### **3.2. UML Diagrams Analysis**

#### **3.2.1. Use case diagram**

###### **TEXTUAL PLACEHOLDER — FIGURE 3.1**

Insert a Race Manager boundary containing UC1–UC12 below. Associate Visitor with UC1; authenticated actors with UC2 and UC7; Driver with UC3, UC5, and UC11; Team Representative with UC4; Race Director with UC6, UC8, and UC9; Administrator with UC10 and UC12. Show higher-role inheritance and the Team Representative specialization of Driver. Associate External Timing Provider with UC7. Use “include” only for genuinely mandatory subflows, such as authorization for protected actions.

##### Figure 3.1: UML use case diagram (placeholder)

#### **3.2.2. Use case identification**

The successful outcomes below assume that server-side validation and persistence succeed. On failure, the system must not report success; any already committed state must be recoverable through a fresh read.

#### **UC1 — Register and authenticate**

- **Actors:** Visitor; registered user.
- **Preconditions:** The service is reachable; login requires an existing account.
- **Trigger:** The person chooses account creation or login.
- **Main flow:** 1. Submit account details or credentials. 2. The system validates them. 3. For registration, it creates a non-privileged account. 4. On successful login, it establishes an authenticated session and shows the appropriate home screen.
- **Postconditions:** A valid account or authenticated session exists.
- **Alternatives/exceptions:** Duplicate identity, invalid credentials, or invalid input produces a clear failure. An expired session requires refresh or renewed authentication. Logout ends the local session and revokes the relevant refresh token.

#### **UC2 — Browse events and inspect an event**

- **Actors:** Authenticated viewer, driver, director, administrator.
- **Preconditions:** Event browsing is accessible to the actor.
- **Trigger:** Open the event list or an event-linked notification.
- **Main flow:** 1. Obtain the event list. 2. Select an event. 3. Read its schedule, format, rules, cost, status, and available participation information.

**3|**

13

- **Postconditions:** The actor can identify the event and relevant next actions.
- **Alternatives/exceptions:** An empty list, deleted event, or unavailable service has a distinct explanatory state.
- **UC3 — Register individually and manage participation**

  - **Actors:** Driver.
  - **Preconditions:** Authenticated participation access; an existing event; no duplicate registration.
  - **Trigger:** Request event registration or cancellation.
  - **Main flow:** 1. Select the event. 2. Submit the required participation information. 3. The system checks format, deadline, duplication, and capacity. 4. It creates the registration in pending confirmation or on the waiting list and displays the outcome.
  - **Postconditions:** One registration represents the participant’s request for that event.
  - **Alternatives/exceptions:** A full event, late request, or unassigned individual in a team event enters the waiting list. Duplicate requests are rejected. Eligible cancellation removes the request; cancellation of a confirmed entry is blocked.

#### **UC4 — Create and maintain a team**

- **Actors:** Team representative; team member; director for administrative changes.
- **Preconditions:** A team-format event; appropriate operational authority.
- **Trigger:** Create/edit a team or leave a team.
- **Main flow:** 1. Supply a team name and teammate identifiers. 2. Validate size and duplicate membership. 3. Create or update the event-specific group and leader association. 4. Notify linked accounts and display the resulting membership.
- **Postconditions:** Team membership is stored consistently within the event.
- **Alternatives/exceptions:** Unknown accounts remain pending email associations where supported. An unauthorized edit or duplicate member is rejected. A non-leader may use the separate leave-team action.

#### **UC5 — Submit an event waiver**

- **Actors:** Driver.
- **Preconditions:** Authenticated identity, existing event, and access to the applicable waiver text.
- **Trigger:** Open the event waiver form.
- **Main flow:** 1. Read the waiver. 2. Enter required personal details. 3. Draw a signature and preview the document. 4. Submit. 5. The system associates the signed data with

**3|**

14

the participant and event and displays signed status.

- **Postconditions:** The signed record can be retrieved by authorized actors.
- **Alternatives/exceptions:** Incomplete details or storage failure prevents success confirmation. Administrative removal or invalidation is reflected in the participant’s status.

#### **UC6 — Configure an event and manage registrations**

- **Actors:** Administrator.
- **Preconditions:** Operational authority.
- **Trigger:** Create/edit an event or review its registrations.
- **Main flow:** 1. Configure event details and participation rules. 2. Review individual and team entries. 3. Admit eligible waiting-list entries to pending confirmation. 4. Confirm entries after external organizer checks. 5. Notify affected participants.
- **Postconditions:** Event settings and registration decisions are available consistently.
- **Alternatives/exceptions:** Invalid limits or state transitions are rejected. Reversing confirmation returns an entry to pending confirmation. Team actions must produce coherent updates rather than partially changed membership statuses.

#### **UC7 — Follow live timing**

- **Actors:** All application users; external timing provider.
- **Preconditions:** A supported timing source is available for selection.
- **Trigger:** Select a source or open the live timing view.
- **Main flow:** 1. Authenticate the connection. 2. Select an allowed source. 3. Retrieve and normalize timing data. 4. Distribute snapshots to subscribers of that source. 5. Display available positions, kart identifiers, lap values, and gaps.
- **Postconditions:** The client follows only the selected source and can identify its connection/data status.
- **Alternatives/exceptions:** An unsupported source is rejected. Provider failure, expired credentials, disconnection, or capacity exhaustion produces an explicit status. Recovery obtains a fresh snapshot.

#### **UC8 — Assign karts and manage session/pit state**

- **Actors:** Race director or administrator.
- **Preconditions:** An existing event and valid entries; operational authority.
- **Trigger:** Assign a kart, start a session, or record a pit/state change.
- **Main flow:** 1. Associate the kart with an entry. 2. Start the session explicitly. 3. Record pit entry/exit as required. 4. Start or stop the session. 5. Distribute the authoritative

**3|**

15

state to affected clients.

- **Postconditions:** Kart assignments and stint values reflect the recorded operational state.
- **Alternatives/exceptions:** A conflicting kart assignment is rejected. Session end preserves elapsed time; pit exit starts a new stint. Automatic event closure follows the separate event policy.

#### **UC9 — Communicate race decisions and manage penalties**

- **Actors:** Race director or administrator; backend stint monitor as an internal initiator.
- **Preconditions:** Existing event and, for a targeted operation, a valid event kart.
- **Trigger:** Submit a message/penalty or detect a stint violation.
- **Main flow:** 1. Select the event, target, and action. 2. Validate the action and applicable rule. 3. Store the message or penalty. 4. Update race state when the action is a global control command. 5. Display messages and accumulated penalty information to relevant users.
- **Postconditions:** The decision is available in the correct event context.
- **Alternatives/exceptions:** Negative penalty durations and kart-targeted global state commands are rejected. Automatic stint assessment records at most one penalty per stint. Authorized penalty removal updates totals without automatically rearming that stint.

#### **UC10 — Import official results**

- **Actors:** Administrator.
- **Preconditions:** Existing event and a results CSV available to the administrator.
- **Trigger:** Choose official results import.
- **Main flow:** 1. Select the event and file. 2. Parse and validate rows. 3. Associate results with entries where possible. 4. If at least one row is valid, replace the event’s existing official results in one committed operation. 5. Report imported count and row issues.
- **Postconditions:** The accepted official classification is available for consultation.
- **Alternatives/exceptions:** A file with no valid results preserves the previous classification. A partial import explicitly reports skipped/invalid information. Unmatched results remain identifiable without falsely associating them with a user. The replacement currently affects all official result types for the event.

#### **UC11 — Consult notifications, results, and performance**

- **Actors:** Driver, team representative; other authenticated users for permitted result views.
- **Preconditions:** An authenticated session; records available for the selected scope.

**3|**

16

- **Trigger:** Open notifications, event results, or personal analysis.
- **Main flow:** 1. Retrieve the actor’s notifications or selected results. 2. Open linked event information. 3. Inspect official classification and available lap summaries. 4. Mark personal notifications as read or delete them.
- **Postconditions:** The actor can distinguish official results from live or other performance information.
- **Alternatives/exceptions:** Missing data is shown as unavailable, not as zero performance. Unmatched results are not silently attributed to the actor. Access to another person’s private notifications is denied.

#### **UC12 — Administer accounts and waivers**

- **Actors:** Administrator.
- **Preconditions:** An authenticated administrator session.
- **Trigger:** Open administrative tools.
- **Main flow:** 1. Find the relevant account or document. 2. Review current data. 3. Apply a role/configuration change or retrieve a signed PDF. 4. Confirm the persisted outcome.
- **Postconditions:** Administrative information is updated or an authorized document is retrieved.
- **Alternatives/exceptions:** Invalid role values, unauthorized access, and missing records are rejected. A removed/inactivated waiver must not continue to appear signed.

#### **3.2.3. Sequence diagrams**

###### **TEXTUAL PLACEHOLDER — FIGURE 3.2**

Show Driver _→_ App _→_ Backend _→_ Registration Store, followed by Director _→_ Backend for confirmation. Include alternatives for duplicate registration, capacity/deadline routing to waiting list, and successful notification creation after the state change.

Figure 3.2: Registration sequence, UC3/UC6 (placeholder)

###### **TEXTUAL PLACEHOLDER — FIGURE 3.3**

Show participant input, preview, authenticated submission, validation, persistence, signed-status response, and later administrator PDF retrieval. Include validation and persistence failure paths.

Figure 3.3: Waiver sequence, UC5 (placeholder)

**3|**

17

###### **TEXTUAL PLACEHOLDER — FIGURE 3.4**

Show Viewer _→_ App _→_ WebSocket Service _→_ Timing Adapter _→_ External Provider. Include source selection, repeated source-scoped snapshots, data interruption, reconnection, and authentication failure. Do not imply direct transponder communication.

##### Figure 3.4: Live timing sequence, UC7 (placeholder)

###### **TEXTUAL PLACEHOLDER — FIGURE 3.5**

Show Director, App, Backend, persisted race state, internal stint monitor, and subscribed clients. Include red-flag pause, green-flag resume, pit exit/new stint, and one automatic penalty when the limit is exceeded.

Figure 3.5: Session and stint sequence, UC8/UC9 (placeholder)

###### **TEXTUAL PLACEHOLDER — FIGURE 3.6**

Show Administrator, App, Backend, CSV validation, and result storage. Include no-valid-row preservation and partial-success reporting, with replacement committed only after validation.

Figure 3.6: Results import sequence, UC10 (placeholder)

### **3.3. External Interface Requirements**

#### **3.3.1. User interfaces**

The interface shall provide role-appropriate navigation, clear empty/loading/error states, and visible confirmation of completed changes. Critical race information shall remain readable without relying only on color. Administrative actions shall identify the affected event, team, kart, or user.

| **View**         | **Required information and interactions**                                             |
| ---------------------- | ------------------------------------------------------------------------------------------- |
| Authentication/profile | Registration, login/logout, profile information, and actionablevalidation errors.           |
| Event list/detail      | Schedule, location, format, limits, cost, status, registration state, andavailable actions. |
| Team management        | Leader, members, unresolved account associations, size limits, andpermitted edits.          |

**3|**

18

| Waiver           | Readable event text, required personal fields, signature area, preview,submission outcome.                    |
| ---------------- | ------------------------------------------------------------------------------------------------------------- |
| Live timing      | Selected source/session, standings, kart identifiers, available lap/gapdata, freshness and connection status. |
| My kart/team     | Assignment, available stint/pit state, penalties, and relevant racemessages.                                  |
| Race control     | Assignments, session controls, pit changes, messages, penalties, andconfirmation of critical commands.        |
| Results/analysis | Official classification, available lap summaries, and explicitmissing-data states.                            |
| Administration   | User/role search, circuits, signed waivers, and result import feedback.                                       |
| Notifications    | Personal messages, read status, and links to the relevant event.                                              |

###### **TEXTUAL PLACEHOLDER — FIGURE 3.7**

Insert labeled mockups or screenshots for login, event details/registration, team membership, and waiver signing. Include at least one validation error and a waiting-list status.

##### Figure 3.7: Participant screen mockups (placeholder)

###### **TEXTUAL PLACEHOLDER — FIGURE 3.8**

Insert a live leaderboard, a personal kart/stint panel, and a director control screen. Show paused session, stale data, and penalty states using text as well as color.

Figure 3.8: Live and race-control mockups (placeholder)

###### **TEXTUAL PLACEHOLDER — FIGURE 3.9**

Insert official results, performance summary, role management, and CSV import feedback screens. Use fictional participant data and distinguish partial import from complete success.

Figure 3.9: Results and administration mockups (placeholder)

**3|**

19

#### **3.3.2. Hardware interfaces**

The initial application uses a touch-capable iOS device for navigation and signature input. No dedicated kart or timing hardware interface is required. Physical lap measurement belongs to the timing provider. Optional location-related experiments in the repository are not a baseline requirement of this RASD.

#### **3.3.3. Software interfaces**

The mobile client communicates with the backend for accounts, events, registrations, waivers, notifications, live operations, and results. Structured requests and responses use JSON, result import uses a CSV upload, and document retrieval returns PDF content. Provider adapters transform supported timing pages into a common representation; unavailable provider fields must remain distinguishable from real zero values.

The CSV interface shall document accepted headers, units, encodings, required classification fields, and participant matching behavior. Import feedback shall identify problematic rows. Detailed endpoint contracts belong in API documentation and must remain consistent with the requirements here.

#### **3.3.4. Communication interfaces**

Production client/server communication shall use HTTPS and WSS. Protected REST actions and live connections require authenticated identity. Timing subscriptions shall remain separated by source; event operation updates shall remain associated with their event. The client shall distinguish its selected source from shared circuit configuration.

Local development may use Bonjour/mDNS discovery and an explicitly selected local endpoint. Development transport settings shall not silently replace production security settings. Connection loss shall be represented in the UI and handled through reconnect/re-authentication as appropriate.

### **3.4. Functional Requirements**

These requirements define the intended baseline.

#### **3.4.1. Identity and access**

| **ID** | **Requirement**                                                                                                             |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| R1           | The system shall create non-privileged accounts from valid registration details andreject duplicate usernames or email addresses. |
| R2           | The system shall authenticate credentials, support session renewal, and supportlogout with refresh-token revocation.              |

**3|**

20

| R3 | The system shall authorize protected actions on the server using the current accountrole and applicable ownership/membership rules; invalid or expired identities shallnot retain protected live access. |
| -- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| R4 | The system shall allow authenticated users to view and update supported personalprofile fields without changing their own global role.                                                                   |

#### **3.4.2. Events and registrations**

| **ID** | **Requirement**                                                                                                                                                                                               |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| R5           | The system shall list events and expose their schedule, location, format, participationlimits, registration cost where specified, and lifecycle status.                                                             |
| R6           | The system shall show a participant’s registration and waiver status separately foreach event.                                                                                                                     |
| R7           | The system shall allow race directors and administrators to create, update, andremove events, validating supplied dates and limits and maintaining consistentdependent records.                                     |
| R8           | The system shall allow eligible participants to register individually and shall preventmultiple registrations for the same linked account in one event.                                                             |
| R9           | The system shall route late requests, requests beyond configured capacity, andindividual requests awaiting a team in a team-format event to `waitlist`; otheradmissible requests shall enter `pending_payment`. |
| R10          | The system shall display registration outcomes and allow eligible self-cancellationwhile blocking ordinary self-cancellation of confirmed entries.                                                                  |
| R11          | The system shall allow an eligible participant to create an event-specific team with adesignated leader, a name, and member identifiers, validating configured team-sizelimits and duplicate identities.            |
| R12          | The system shall restrict participant team edits to the relevant leader and provide aseparate non-leader departure operation; administrative changes require operationalauthority.                                  |
| R13          | The system shall let race directors and administrators admit waiting-list entries,confirm pending entries, reverse confirmation, and remove entries, applying team-wideoperations consistently.                     |
| R14          | The system shall report invalid registration transitions without partially applyingthem and shall retain an understandable distinction between membership,confirmation, and signed-waiver status.                   |

**3|**

21

#### **3.4.3. Waivers**

| **ID** | **Requirement**                                                                                                                                                        |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| R15          | The system shall present the applicable event waiver text and allow the participant topreview the document before submitting required personal details and a drawnsignature. |
| R16          | The system shall associate a successfully submitted waiver with its participant andevent and display signed status only after successful storage.                            |
| R17          | The system shall provide authorized administrative consultation and PDF retrieval ofsigned waivers and shall reflect removal/invalidation in the participant’s status.      |

#### **3.4.4. Live timing**

| **ID** | **Requirement**                                                                                                                                                         |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| R18          | The system shall allow authenticated viewers and higher roles to subscribe to anallowed supported timing source without altering another client’s source selection.          |
| R19          | The system shall retrieve and normalize available provider standings, including kartidentifiers, positions, lap values, and gaps where supplied.                              |
| R20          | The system shall distribute each timing snapshot only to clients subscribed to itssource and distribute event updates within the correct event context.                       |
| R21          | The system shall identify unavailable/stale timing or disconnected service state andobtain a fresh snapshot on recovery instead of presenting retained information ascurrent. |

#### **3.4.5. Race operations**

| **ID** | **Requirement**                                                                                                                                                          |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| R22          | The system shall allow authorized officials to associate event kart numbers withentries and shall reject conflicting simultaneous assignments of the same kart withinan event. |
| R23          | The system shall maintain event lifecycle separately from session operational stateand require an explicit start action for a new session after stop.                          |

**3|**

22

| R24              | The system shall advance stint time only while the session is running and theassigned kart is on track; pause and pit entry shall preserve elapsed time, while pitexit begins a new stint.                                                                                  |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| R25              | The system shall make the participant’s relevant kart assignment, stint/pit state,penalty total, and applicable messages available for consultation.                                                                                                                       |
| R26              | The system shall let authorized officials record broadcast or kart-targeted messages;commands changing global session state shall not accept a single-kart target.                                                                                                          |
| R27              | The system shall let authorized officials record and remove penalties with a validtype, optional non-negative time value, and explanatory note, and shall updatedisplayed totals accordingly. Configured warning thresholds shall trigger theirspecified automatic penalty. |
| R28              | The system shall evaluate configured stint limits on the backend, issue at most oneautomatic stint penalty per stint, and avoid reissuing that penalty merely because itwas deleted. A new stint resets eligibility for assessment.                                         |
| R29              | Under the provisional expiration policy, the system shall close scheduled or startedevents 48 hours after their scheduled start and notify connected clients of the lifecycleupdate; this shall not constitute result publication.                                          |
| **3.4.6.** | **Results, notifications, and administration**                                                                                                                                                                                                                        |

| **ID**     | **Requirement**                                                                                                                                                                                                          |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| R30              | The system shall restrict official CSV import to administrators, validate rows beforereplacing official event results, report partial import issues, and preserve the previousclassification when no valid rows are available. |
| R31              | The system shall provide permitted event results, personal result history, and availablelap summaries, distinguishing official data and unavailable participant associations.                                                  |
| R32              | The system shall provide recipient-specific in-app notifications for relevantregistration/team/waiver changes and reminders, with read/delete operationsrestricted to the recipient and event links where applicable.          |
| R33              | The system shall allow administrators to search accounts and assign supported roles;ordinary users shall not perform these changes.                                                                                            |
| R34              | The system shall allow administrators to maintain circuit information, supportedtiming-source configuration, and shared waiver settings.                                                                                       |
| **3.4.7.** | **Traceability**                                                                                                                                                                                                         |

**3|**

23

| **Goal** | **Requirements**                  | **Use cases**          | **Main assumptions** |
| -------------- | --------------------------------------- | ---------------------------- | -------------------------- |
| G1             | R1, R2, R4–R10, R13–R17, R32          | UC1, UC2, UC3, UC5,UC6, UC11 | D1, D4, D5                 |
| G2             | R11–R14, R22, R24, R25, R32            | UC4, UC8, UC11               | D1, D3                     |
| G3             | R18–R21                                | UC7                          | D2, D7                     |
| G4             | R7, R13, R14, R22–R29                  | UC6, UC8, UC9                | D1, D3, D8, D9             |
| G5             | R3, R17, R33, R34                       | UC12                         | D4, D6                     |
| G6             | R30, R31                                | UC10, UC11                   | D2, D3                     |
| G7             | R2, R3, R6, R10, R14, R16, R20,R21, R32 | UC1–UC12                    | D6, D7                     |

#### **3.4.8. Acceptance examples**

| **Check** | **Given / When / Expected outcome**                                                                                                                     | **Coverage** |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------ |
| A1              | Given an existing registration, submitting the same participant/eventagain does not create a second entry.                                                    | R8                 |
| A2              | Given a passed deadline, an otherwise valid new request enters thewaiting list and is visibly labeled.                                                        | R9                 |
| A3              | Given a participant account, attempting a role change or anotherteam’s edit is denied server-side.                                                           | R3, R12, R33       |
| A4              | Given two clients subscribed to different sources, an update from onesource does not appear on the other client.                                              | R18, R20           |
| A5              | Given a running stint, stop freezes elapsed time and pit exit starts anew stint.                                                                              | R23, R24           |
| A6              | Given an exceeded stint limit and no mobile clients, backendassessment creates one penalty; repeated assessment and deletion donot recreate it in that stint. | R28                |
| A7              | Given published results, importing a file containing no valid rowspreserves those results and reports failure.                                                | R30                |
| A8              | Given a successfully submitted waiver, its status and authorized PDFretrieval identify the correct participant and event.                                     | R16, R17           |
| A9              | Given a stopped session, a green flag does not restart its timers; anexplicit new start does.                                                                 | R23                |

**3|**

24

A10 Given an interrupted provider feed, the interface displays R21 stale/unavailable state instead of claiming current timing.

### **3.5. Performance Requirements**

The following values are proposed targets for stakeholder review, not measured service guarantees.

| **ID** | **Proposed measurable target**                                                                                   |
| ------------ | ---------------------------------------------------------------------------------------------------------------------- |
| P1           | At least 95% of ordinary event/profile/registration API requests complete within 2seconds under the reference load.    |
| P2           | At least 95% of normalized timing snapshots reach subscribed clients within 1 secondof backend acceptance.             |
| P3           | The UI indicates lost connectivity or absent expected timing updates within 10seconds.                                 |
| P4           | A continuous stint-limit violation is assessed within 2 seconds of exceeding the limitduring normal backend operation. |
| P5           | A CSV returns an import outcome within 5 seconds after upload completion.                                              |

Resource limits shall fail with a clear response rather than silently attaching a user to the wrong source or losing committed operations.

### **3.6. Design Constraints**

#### **3.6.1. Regulatory and organizational policies**

The system handles personal information and drawn signatures. Requirements for permitted processing, retention, deletion, and waiver wording must be supplied and approved by the responsible organization before operational release. This document does not establish legal validity of a drawn signature or claim compliance certification.

Access to signed documents and personal details shall follow the role and ownership requirements. Demonstration data and screenshots should use fictional identities.

#### **3.6.2. Hardware and software limitations**

The initial release is constrained to the existing iOS/backend deployment. Browser-based data acquisition consumes backend resources and depends on provider availability and page structure. The initial persistence technology requires verification under the agreed concurrent workload. Mobile clients cannot be assumed to remain connected or active in the background.

**3|**

25

Consequently, automatic stint assessment belongs to backend behavior, and the timing interface must tolerate missing data. Offline race control and hardware-level lap timing are outside the baseline.

### **3.7. Software System Attributes**

| **ID** | **Attribute** | **Requirement and verification approach**                                                                                                                                                                                |
| ------------ | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Q1           | Availability        | A single provider outage shall not prevent unrelated source subscriptionsor ordinary event/account operations. Verify by disabling one providerwhile using another.                                                            |
| Q2           | Reliability         | Committed registrations, waivers, results, and race decisions shall survivea normal backend restart. Interrupted operations shall not be reported assuccessful. Verify restart and transaction-failure scenarios.              |
| Q3           | Security            | Production transport shall be encrypted; passwords shall not be stored asplaintext; authenticated identity and permissions shall be enforced on theserver. Verify direct unauthorized requests in addition to UI restrictions. |
| Q4           | Privacy             | Private notifications and waiver records shall be accessible only to theirpermitted recipient/owner or authorized administrative role. Verifycross-account and direct-document access attempts.                                |
| Q5           | Usability           | Important statuses shall have text labels, and invalid actions shallprovide an understandable recovery step. Review the participant anddirector workflows, including errors and empty states.                                  |
| Q6           | Maintainabili       | tyA new timing adapter shall map to the common timing contract withoutchanging registration or waiver behavior. Verify adapter isolation andregression coverage for those independent workflows.                               |
| Q7           | Portability         | Domain operations shall be exposed through documented serviceinterfaces so future clients can reuse them.                                                                                                                      |
| Q8           | Consistency         | Dates and elapsed times shall have explicit units, and updates shallpreserve event, participant, and source identity. Verify deadlineboundaries and simultaneous independent events.                                           |
