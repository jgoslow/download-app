Onboarding questions:
* This latest version is pretty good - and I want to generate a few different versions of the onboarding workflow to determine how well they do against eachother.  So keep this as a version (use letters and numbers to identify them)
* New Version
  * "Welcome to your first flow." (2s auto-advance)
  * "Speaking out loud is the best way to use Basn — but you can always switch to text at any time by hitting the keyboard icon at the bottom." (6s auto-advance)
  * "What would you like to use Basn for?" — chips: Work / Life / Growth / Something else (required)
  * "What does a typical day or week look like for you?" — detail: "Share as much or as little as you   * like."
  * "Which tools do you use?" — chips: Jira / GitHub / Slack / Toggl / Google / Wave (required)
  * "Basn creates workflows for you automatically — connect the tools and it figures out where your   * thoughts should go." (8s auto-advance)
  * "What outcomes matter most to you?" — chips: Tasks / Messages / Time logs / Reminders / Journal   * (just added)
  * "When do you usually want to capture your thoughts?" — chips: Morning / Evening / Midday / Whenever
  * "Anything else you want Basn to know about how you work — or what you're hoping to get out of it?" (required)

Use the first flow as a baseline to generate a number of new onboarding flows with the following goals:
1. Get the user used to a Basn flow so they can do it again.
2. Establish a connection to at least one tool, though ideally a few (since many will be free).
3. Setup a simple, achievable daily or weekly flow.
4. 

"Welcome to your first flow." (2s auto-advance)
"Speaking out loud is the best way to use Basn — but you can always switch to text at any time by hitting the keyboard icon at the bottom." (6s auto-advance)
"What would you like to use Basn for?" — chips: Work / Life / Growth / Something else (required)
"What does a typical day or week look like for you?" — detail: "Share as much or as little as you like."
"Which tools do you use?" — chips: Jira / GitHub / Slack / Toggl / Google / Wave (required)
"Basn creates workflows for you automatically — connect the tools and it figures out where your thoughts should go." (8s auto-advance)
"What outcomes matter most to you?" — chips: Tasks / Messages / Time logs / Reminders / Journal (just added)
"When do you usually want to capture your thoughts?" — chips: Morning / Evening / Midday / Whenever
"Anything else you want Basn to know about how you work — or what you're hoping to get out of it?" (required)

Daily Tasks, expectations, goals
* Basn is geared strongly towards helping people make good use of their day, and therefore a morning flow should result in a list of tasks, meetings, subjects, goals...etc and we can provide some easy ways to follow up on them.  That list of tasks or daily goals becomes global context for any subsequent flow, but also could be a widget on the Basn home screen, or maybe in iOS to take stock of what you said you were going to do that day.
* Do we generate a shortlist of daily tasks that resets each day and just gets amalgamated into the following flow you run?
* Do we generate a list of daily goals or objectives and check in at the end of the day or sometime during the next flow to see whether they've been completed/accomplished?


---

Feeedback:
* 

---

Feedback
* THe Transcript should be separated out by prompt (if there's one showing), and definitely be chronological, that way the context can be set against the prompt.
* What outcomes matter most to you - should use chips to show the common ones.
* Still skipping the tools onboarding phases, went straight to "All Set"

---

* The start flow button should be disabled until the transcription model download completes
* Ending with "You can connect tools any time in settings" is not really the outcome I was going for.  Instead, it should go BACK to the onboarding screens with a screen for each tool to integrate it.  Look at my original onboarding flow list. We should connect one tool at a time INSIDE the onboarding screens. Basically the onboarding experience extends to match whatever the user talks about and wants to connect, including surfacing the workflows extrapolated from the transcript AND and initial suggested flow.  You can drop in some placeholders for those parts but the tools should be straightforward to add now.
* Gonna make a change to the flow screen layout: 
  * Let's make the main flow button live in the center of where the dot nav is - so the "current" dot is the main flow button, and would change slightly based on the type of prompt.  Pressing the main flow button no longer ends the flow, but instead it will proceed to the next one (it's like marking that prompt step complete). Pressing the main flow button should first change it to a checkmark and then move to the next one.
  * Move the Mic and Keyboard icons to the lower left below the dot nav.
  * In the lower right of the flow experience is the flow name, which you can click to select a different flow while the flow is recording.
  * If the user does NOT give mic permissions, then keyboard becomes the default flow input until they do.
  * I'm not seeing the transcription show up at the top of the flow experience, was that built yet?
  * Can we read the flow transcript in real time without sending it to Claude?  For instance, if the user says "next prompt" or "next." (important that we distinguish between the word "next" on it's own or in a sentence) it could go to the next prompt.
  * pressing and swiping side to side anywhere on the dotnav (even on the main button) should advance/retreat the prompt-nav state.  When pressed down on the dotnav after a short delay a small preview of the currently selected prompt question should appear above the main button - if you swipe at all the main while pressed down then the preview updates would update as you move the dotnav - once you let up then the preview disappears and the main prompt updates.
  * Remove the keyboard switch from the main nav area and change the start flow button to a "flow" icon.  Clicking it moves the flow button up as the dark background navigates in to cover the rest of the interface, then the dots and the first prompt flow in.


---

Let's add some further flow definition and add more steps to the Basn onboarding "Welcome" flow and automate some of the setup for tools and workflows. These steps will apply to both apps. I'm also defining flows more and a new flow prompt logic.

"Welcome Flow"
I'm thinking we do this after model selection/mic-approval in the onboarding:
1. start with the following: "Basn works by capturing your thoughts as you speak (or type) and surfacing prompts for you to speak to during a flow session. Prompts can come from the flow, things you've said before, or even other sources - let's try it out by doing a **setup flow**."
  * "Start Flow" with the "start button" lockup (with text switcher as well) below it
  * Underneath should be a "skip setup" link - this will remain through all subsequent setup steps (I'm not sure there will be any subsequent steps yet, it might just be one flow).
2. Enter **setup flow** that will surface prompts to get the information we need out of the user.  This represents net-new functionality for Basn, and will be one of the core differentiators. See notes on Flow prompts, and create a setup flow using the bullets below (suggest a series of flow prompts to use):
  * timed 2s - Welcome to your first flow, (only show if this is the first flow)
  * timed 5s - Speaking out loud is the best way to use Basn, but you can switch back and forth with text input during a flow.
  * required - Some prompts have inputs you can tap or just speak aloud, such as "What would you like to use Basn for?" [Work, Life, Growth, Other]
  * what tools
  * what workflows
  * Basn can't prepare for every scenario in your life, but we can create useful channels for some common outcomes and not-so-common outcomes in your life, and for everything else our goal is to capture your thoughts and give you an output you own that you can do with what you will.  There's great potential for automations, but ultimately the core value is the ritual, it's the capture. How do we teach this succinctly, in bit-size chunks?
  * suggest outcomes they might like to facilitate with Basn (A/B/C test this when we go live - maybe ask about it to begin with)
  * Based on open-ended share out, here are the spheres we heard, do you want to add XYZ ones?
  * here are some workflows we heard, do you want to add XYZ ones?
  * here are the tools we heard, are there any others you use to do XYZ? (verify sphere?)
  * here are the workflows we heard, how do they look? (verify sphere?)
  * Flow setup - recommend a cadence for the user (does this go first?)
    Maybe we just have them add one flow to begin with and suggest more later?  Build in a habit. Or will everyone end up with the same kinds of flows - daily (1-3), weekly, quarterly, scheduled, occasional..
  * We've saved a setup list for the plan, so you can come back to this anytime to complete - any final thoughts before we connect your tools and finish setup?
  * List the spheres we've determined.
  * One by one, request access to the tools they want to use (note any apps that will require approval if used on the other platform)
  * List the workflows and their respective tools, give a change for feedback/adjustments
  * Suggest an initial flow for the user to start with and a ritual
  * Outcomes: Setup Tools, Workflows, and initial Flow and message: "Well done. I've got a reminder scheduled for XYZ. Do you want to do a quick flow now? [open flow][named flow]"
  * Questions: How many anthropic interactions are needed for this flow? Is it necessarily an expensive flow?


Flow Screen and Prompt Logic
* When in a flow, the user should be able to see a live transcription of their flow appear in light (low-contrast readable) text starting near the top and flowing up off the flow screen as it transcribes (this would appear as the user submits for text input).  It should only show the last 3 sentences or so so it doesn't take up too much space.  However, a user can drag down on the upper transcript area to scroll through the transcript (and the text takes over the flow space hiding whatever else is there) - an up arrow will appear in the top right to scroll back to the minimized state or they can do it by swiping up.
  * Let's start with the mobile UI and then we'll decide/ideate on how the Desktop one can be different, since it isn't so constrained.
* A flow definition should be stored as a plain-language .md file generated by the Castellum along with any meta-data (JSON? YAML?) the app requires. Flow capture transcripts should be stored as their own file along with outcomes. During a flow and after it completes the castellum can process the flow transcript to generate a flow capture summary with outcomes, suggested workflows (and then which ones were triggered after approval), and any other context that's relevant. The flow capture summary is also processed to update a flow context file which is used along with the flow definition to inform the next capture for that flow. The audio can be deleted after X days (is this an app setting, I like that) - but if it's not deleted yet then I suppose the user could play it back or mark it for saving if they wanted.
* The ability to prompt users as they're in a flow is one of the core features of Basn.  The prompts will come from the castellum (which processes the flow definition and context), but Basn can develop a broader intelligence to help people deepen their flows based on the user's stated and perceived goals.  We can develop this out as we go - but for now just take note of making a plan to build out the Basn prompt intelligence.
* Prompts show as short questions, considerations or other notes in the center of the flow screen. They are not meant to be permanent, necessarily. Sometimes the prompts include single or multi-select inputs answers the user can tap (though it must be limited). The prompt text fades in and out when transitioning - and there should be a dot for each prompt in the flow at the bottom like dot nav (though we don't need to fit all of them on the screen at once if they're a lot of them, they are also dynamic, to some degree) The first prompt dot starts in the middle and subsequent dots go off to the right, they flow in from the right and off to the left, so a user can always swipe left or right in the prompt area or on the dots to navigate the prompts. The "active" prompt dot should be in the center and animates into a bigger circle. The flow prompts advance automatically based on timers or "completion" states, but also sometimes surface based on decisions from the castellum. We will likely color-code the prompt-types, but I'll iterate into that.
  * The "active" prompt circle should animate subtly depending on the type. 
  * Always take a beat between prompts, and as a rule (unless otherwise stated in a prompt) - wait for a pause in speech to load the next prompt. Having no prompt on screen is okay - the point of the flow is the user's train of thought, first and foremost.
  * Some prompts are timed - Outlined and filled with liquid in it that slowly empties out as the prompt timer clears. Once the timer ends the prompt fades out and goes to the next prompt if there are any.
  * Some prompts are required or meant to be answered and don't have a timer, and will pass only when they're answered or the user swipes past them - outline with transparent fill. 
  * Un-timed prompts - The castellum should actively check the flow transcript (or user-selected prompt input answers) in real-time (every 2-3 seconds?) while on an untimed prompt to assess whether the prompt has been answered, and then fill the dots and advance when they are - perhaps the prompt could change state slightly when it's "answered" and start a short timer to advance.  Castellum could also attach a short description of the answer to show below the question if the user swipes back.
  * Some prompts are required (solid, bright, usually at the beginning of the flow, and I believe they would always be un-timed)
  * Some prompts are optional (more transparent, grey, usually at the end, but not always - probably timed mostly). 
  * Some prompts are surfaced or improvised by the Castellum, and are added dynamically in the prompt timeline as a result of processing the transcript in real time. 
  * Prompts aren't only about answering questions - they can also be inspiration for the user's flow (which could take a lot of forms), or maybe they're follow-up on something the user said before.
  * The Castellum should pre-process a list of possible prompts for any given flow - they come from a few places:
    * The flow definition itself could either have a list of prompts (required and optional) or a description of the kinds of prompts to include and the Castellum generates them each time.  
    * If the user has done a flow previously, there should be a historical context file attached to that flow that the subsequent flow can use to prepare prompts. It could be following up on a specific topic or reminder, it might be introducing new or deeper topic discovery...etc.  This is the underlying Basn intelligence that we can iterate in as we test. It would be ideal if most or all of the core castellum logic can be done with an open-source or free model (or just good old algorithms) - but we can hit Claude as needed for now.
    * The current flow transcript will periodically be processed in real-time and may inspire the Castellum to generate new prompts.
* Flow prompts - each flow should define suggested prompts to use and their definition (required, timed..etc).  At the beginning of every flow capture (or end of the previous one if that's more efficient) Castellum decides what prompts to include at the start and can add new prompts to the prompt timeline (or potentially "answer" or remove prompts that haven't been seen yet).  Flows don't need to have a lot of prompts to be effective, and a flow doesn't need to be processed in real-time a great deal by the Castellum to be successful.
  * Should we have any dynamic processing of flows to begin with?  How about v1 could just be a fixed list of prompts that have a set timer and the user can swipe through them at will and everything is processed once at the end (including a list of questions for the next time the flow is run).  v1 is low-cost, low-overhead. v2 includes more dynamic processing points.

Flow Scheduling and Reminders
* Most, if not all flows, have a pre-defined schedule they run on.
* A flow schedule triggers a reminder with a link to start the flow - there should be the option to skip.
* After skipping a flow 3 times, it should prompt the user if they want to reschedule the flow, change the cadence, or dismiss for now. This kind of reminder can come up again after skipping another 5 times, and then let it go (unless they say "dismiss for now"). 

Flow Tracking and Privacy:
* Let's build out a plain-english privacy page to outline how Basn captures flows and what is tracked. Include examples of what is stored on their device (simple sample JSON) vs. what Basn keeps (only the barest details)
* All personal data is stored on the user's device. Flow audio is never saved. Flow transcripts are stored on the user's iCloud account (include details). 
* We can capture basic, anonymous flow data (flow id, length, list of tools used, number of workflows triggered), tokens used, prompts given and answered, 
* Notifications, notification click-throughs, notification dismissals, with basic-anonymous notification type metadata in all cases (type?...)
* Create a plan for tracking other activity in a similar, non-personal kind of way.  We want to be able to debug and optimize our experiences, but not at the expense of privacy. Is it normal to ask for opt-in to this?  We could share examples of how we share when we ask for opt-in?..

Spheres or destination areas:
* I don't know if we need this convention, but in allowing people to capture flows that cover multiple aspects of their life, we have to gracefully segregate the private from the work-related, the personal from the public workflows, the exposed and proprietary.  This is not simple, and is one of the reasons that users should approve the outcomes and vet any outward facing actions.  Drafts will be important.
* Perhaps part of capture summary is distinguishing anything that was shared that might be private. Maybe the Castellum can surface questions for the user in between sessions that show up on the homepage - they can clarify how careful/aware the user wants to be with their thoughts, opinions...etc being free in your share outs is important.  I'd say generally having a private outlet for personal thoughts to go is important, but relying on Basn to always know what's personal or not is tough.  Also, is there a way to prevent this kind of information from going to Claude?  What are claude's protections?  What are each model's protections?
* If it is important, spheres are a way to designate the areas of Basn's engagement in a person's life - this part of the capture output goes to work, this part goes to personal life, this part relates to personal growth.  Once determined (and it could be logged and verified by the user if needed), then the appropriate workflows can be determined.  It could surface gaps in the workflows because the outputs have been designated a sphere, and even if another workflow exists for a certain outcome, the sphere may not match, and therefore a new workflow is needed.
* One manifestation of this is the potential need for two tools that do the same thing.  I have multiple gmail accounts - personal, lyra, and 2 or 3 client-specific emails they've created for me to work within their ecosystems.  Can Basn adequately manage and distinguish between them?  To begin, we can just start with one tool connection, but I think we'll quickly need more.  And it could be very helpful to designate a specific tool as available for one or more spheres. That kinda has legs as a mental model. 

Setup steps to show for a homepage component:
1. Connect Microphone
2. Download and Select Transcription Model (for desktop)
3. Run **Setup Flow**
  a. determine spheres or desintations (such as "work", "self-growth", "life/journal", "XYZ side project") - the Castellum decides how to separate flow transcripts into workflows/actions based on this. 
  b. connect tools
  c. verify workflows
  d. create your first flow
4. Perform your first flow


Notes:
* Allow pasting text or images?
* For future - speak out the prompts, but have a pleasant chime to indicate when the prompt is about to happen, and wait until the user stops talking to talk - unless they keep talking past a certain timeout, in which case the chime would happen again - that way the user can finish their thought, and the chime helps create as sub-conscious pseudo-conversational pattern that doesn't create lots of awkward interruptions like on robo-calls.
* Do a brainstorming session about what personal growth could look like on Basn, what life flows look like on Basn, what the less visible, less outcome oriented things look like on Basn.  What is the less obvious, intangible (and feeling) value of the ritual? What is the psychology behind that?  Is it mindfulness?
* Even thought we're not building a UI expression for goals, I would love the castellum to try to guess at the user's goals based on what they say (or maybe they say it explicitly). Basn could delineate between goals that the user is (or could be) working towards through Basn vs. general goals they have, though maybe the distinction is moot, ultimately. Maybe this is a separate goals.md file.
* This is really easy to gamify - I don't want to overemphasize that though.  What about gamifying through reinforcing good habits in acknowledgements.  Basn knows their goals - maybe it's providing a realistic assessment of how they've been progressing towards those goals (as far as we've seen).
* Text input - Can this open a default keyboard with message area similar to something like Slack, and then you submit the message? 

---

Added the video - Make sure the video has a black transparent scrim over it.

Correction on the record UI changes.
* The mic/text icons (larger, smaller icons) should go in the menubar as the center icon - we don't need them in the main screen.  So it should only take one click to start a flow, and once you're in a flow then the "flow screen" appears.  We're going to add a bunch of functionality to it.


---

Slogan ideation:
* Let your thoughts flow
* Catch your stream of consciousness
* Put your thoughts to work
* Empty your mind. Fill your cup.
* Simple. Consistent. Rituals.
* 


---

iOS:
* Onboarding screen should be in dark theme with video of water flowing in background? Can we get a few simple videos of water flowing through channels of different kinds? It could also include things like water mills, dams, irrigation, roman devices/inventions, water clocks...etc. Curious what you find.
* The middle record button should be slightly larger than the menu bar and be a blue circle like on the current record screen. It should have a small keyboard icon to the top left of it that can be clicked to "use type" and switch the record button to a keyboard icon that opens the keyboard. When "use type" selected, the top left small icon switches to a microphone to allow for switching to "use voice". It's just a toggle essentially. Try out a simple animation between the two.
* The starting screen for iOS should be a kind of "welcome" screen with shortcut buttons to the 3 most recently used flows (if any), a summary of the most recent transcription, and maybe you have suggestions for what can go below.  When a user is new, if they skip onboarding (we'll get to that), it should have a list of the onboarding setup steps and which ones they've completed.  They can always click into a step after the fact.

Keep these for reference:
* Pexels — Shiny particles in dark water — dreamy, abstract
* https://pixabay.com/videos/water-wheel-mill-hydropower-energy-4951/
* https://www.pexels.com/video/a-dry-irrigation-canal-in-the-countryside-12178840/
* https://www.pexels.com/video/bird-s-eye-view-forest-brook-stream-19288786/

Use this one for the background:
* https://pixabay.com/videos/water-wheel-old-water-mill-94004/



---

Use this for the intro now:

Capture your stream of consciousness and channel it.. 

Basn gives you a place to to privately capture your free-form thoughts aloud and put them to work - mix work and life, simple notes, personal journals or even complicated workstreams. Use it for daily self-growth rituals and personal work check-ins at the same time, all connected to the tools you already use. Let's get started.

Basn - let your thoughts flow.

---

* Selecting a model is the wrong experiencea here.  Instead let's start download Parakeet TDT v2 for english, and the second step will be "Select a language" with two options:
1. English, at the bottom say "Model downloading" with the button filling up as it downloads or "Model downloaded" with a checkmark.
2. Multi-lingual
At the bottom we have "Back" link, "see all models" link, and the "Next" button.  If the selected model isn't downloaded fully yet then the button would say "Model still downloading" in a disabled state.  
the "see all models" link would show the original "select model" experience with one difference - as soon as a model is selected it starts downloading and you see the progress in the background of the radio button (like on the English/Multi-lingual screen). Downloaded model options have a green check instead of the download icon (clicking the download icon just selects that model and starts the download).
If the user selects Multi-lingual then it immediately starts downloading and would also would have the Downloading/Downloaded state. Any unselected and partially-downloaded option could still keep the progressing fill state to show how far it downloaded.
When moving to the next step, delete any partially downloaded models.

---

Talk out loud and Basn writes it down and sends it where it needs to go.

Basn - Let your thoughts flow.

---

Basn is an AI-powered capture and productivity app for iOS, macOS and Apple Watch.

Pour your thoughts into Basn with daily ritual flows, and build channels for your ideas to go to work. Capture your thoughts by voice, let AI analyze them, and route workflows to the tools you connect. Create channels to support your personal and work life goals. Basn helps you build practical pathways for your ideas and empty your mind on a daily basis.

Basn - Let your thoughts flow.

--

Your mind is full to the brim - ideas, reflections, projects, tasks pooled in the dark recesses of your brain. What if you channeled them towards something useful and made space for what's next? Notes, journals, messages, tasks, reminders, coordination and execution.. make daily rituals to capture and release, delegate and excecute.  Catch your stream of conciousness and put it to work.

Basn - Let your thoughts flow.


