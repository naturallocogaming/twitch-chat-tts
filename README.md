# 🔊 ChatTTS — Twitch Chat TTS Bot

> **I wanted Twitch Chat to talk to me. So naturally, I built the entire fucking thing in PowerShell.**

ChatTTS is a cross-platform Twitch Chat Text-to-Speech bot written in **PowerShell 7+**.

It connects directly to Twitch Chat over IRC, handles Twitch OAuth, filters and moderates incoming messages, queues them up, sends them to a locally hosted **FastKoko TTS API**, and plays the resulting audio on the streaming machine.

Because apparently the correct response to:

> *“I sometimes don't notice when people talk to me while I'm streaming.”*

is:

> *“I should build a distributed-ish voice processing system.”*

And here we are.

---

## 🎤 What Does It Do?

ChatTTS takes messages from your Twitch chat and makes them talk.

The basic pipeline looks something like this:

```text
                   ┌──────────────┐
                   │    TWITCH    │
                   │     CHAT     │
                   └──────┬───────┘
                          │
                          ▼
                   ┌──────────────┐
                   │  Twitch IRC  │
                   └──────┬───────┘
                          │
                          ▼
                ┌───────────────────┐
                │    PowerShell     │
                │                   │
                │  • Filtering      │
                │  • Moderation     │
                │  • Commands       │
                │  • Queueing       │
                │  • User settings  │
                └─────────┬─────────┘
                          │
                          ▼
                  ┌───────────────┐
                  │  FastKoko TTS │
                  │      API      │
                  └───────┬───────┘
                          │
                          ▼
                    🔊 AUDIO 🔊
                          │
                          ▼
                    😎 ME HEAR
```

The entire speech generation process can run locally.

No per-message cloud TTS bill.

No subscription.

No third-party TTS service deciding to fall over halfway through your stream.

And, most importantly:

**Chat can yell at me even when I'm completely locked into a game.**

---

# ✨ Features

ChatTTS currently includes:

### 🗣️ Twitch Chat → Speech

* Connects directly to Twitch Chat using IRC
* Reads chat messages aloud
* Supports multiple TTS voices
* Uses a locally accessible FastKoko TTS API
* Cross-platform audio playback

### 🎭 Per-User Voices

Chat can customize how their messages sound.

```text
!voices
```

Shows the available voices.

```text
!myvoice
```

Shows your current voice.

```text
!setvoice af_bella
```

Sets your preferred voice.

The bot remembers your preference in `UserVoices.csv`.

So when you come back next stream, Chat remembers exactly which voice you wanted.

Because apparently we're giving Twitch users **character development** now.

### 🛡️ Moderation

Because giving the internet a microphone without moderation is how civilizations collapse.

ChatTTS supports:

* Banned words
* Link filtering
* Maximum message length
* Emote filtering
* Follower-only restrictions
* Subscriber-only restrictions
* Ignored bots
* Twitch channel point redemption filtering
* Per-user message cooldowns

Banned words live in:

```text
BannedWords.txt
```

One entry per line.

Customize it for your own channel.

---

# 📋 Message Queue

Chat messages don't immediately pile-drive themselves into the TTS engine.

They're queued.

Each message contains:

* Username
* Message
* Selected voice
* Timestamp

The bot then processes them sequentially.

There's also a per-user cooldown so one person can't completely monopolize the voices.

Because yes, **I know what Twitch chat is capable of.**

---

# 🎛️ Console Controls

The bot has a little console UI because apparently a PowerShell script wasn't enough.

While it's running:

| Key     | Action                                      |
| ------- | ------------------------------------------- |
| `N`     | Toggle automatic chat notification messages |
| `L`     | Send a notification immediately             |
| `Enter` | Play the next queued message                |
| `P`     | Pause / Resume queue playback               |
| `K`     | Skip the currently playing message          |
| `S`     | Stop and clear the queue                    |
| `D`     | Toggle debug logging                        |
| `E`     | Exit                                        |

The console also displays:

* TTS status
* Queue status
* Notification status
* Currently playing message
* Message queue
* Recent debug messages

It's not pretty.

It's a PowerShell console.

**What did you expect?**

---

# 🧠 Why PowerShell?

Because I know PowerShell.

Could this be written in Python?

Absolutely.

Could it be written in C#?

Sure.

Could someone build a web application around it?

Please don't. ಠ_ಠ

The point of this project is that **I understand the code I'm running.**

I'm a Platform Engineer / Systems Architect by day, so PowerShell is something I already know extremely well.

This project is also an excuse to take a tool I normally use for infrastructure automation and use it for something significantly less responsible.

---

# 🏠 Local TTS

The bot is designed around a locally accessible TTS API.

I'm currently using **FastKoko** with Kokoro for speech generation.

The PowerShell script sends a request containing:

```json
{
    "input": "Natural Loco says: Hello chat!",
    "voice": "af_bella",
    "response_format": "mp3"
}
```

FastKoko generates the audio.

PowerShell saves the result temporarily.

Then the appropriate local audio player takes over.

Simple.

Well...

Simple **now**.

---

# 💻 Cross-Platform Audio

ChatTTS supports several audio playback options depending on the operating system.

### Windows

Uses:

* `ffplay`
* Windows `SoundPlayer` as a fallback

### macOS

Uses:

* `afplay`

### Linux

Uses:

* `mpg123`
* `ffplay` as a fallback

So yes.

The same PowerShell script can run on Windows, macOS, or Linux.

Because if I'm going to over-engineer something, I'm at least going to make it portable.

---

# 🚀 Prerequisites

You'll need:

* **PowerShell 7+**
* A registered **Twitch Application**
* A Twitch OAuth redirect URI configured as:

```text
http://localhost:8080/
```

* A reachable **FastKoko TTS API**
* One of the supported audio players:

  * `ffplay` / FFmpeg
  * `mpg123`
  * `afplay` on macOS

---

# 🧰 Twitch Application Setup

Create a Twitch application through the Twitch Developer Portal:

[Twitch Developer Portal](https://dev.twitch.tv?utm_source=chatgpt.com)

Configure the OAuth redirect URI as:

```text
http://localhost:8080/
```

**The trailing `/` matters.**

The bot uses a local HTTP listener to receive the OAuth callback.

On first launch, it will open the Twitch authorization page in your browser.

After authentication, the bot saves the resulting tokens to:

```text
bot_token.json
```

The token is reused on subsequent launches and refreshed when necessary.

### ⚠️ DO NOT COMMIT `bot_token.json` or your `CHAT_TTS_CLIENT_ID`  & `CHAT_TTS_CLIENT_SECRET`

Seriously.

Don't put your Twitch access or refresh tokens on GitHub.

Add it to `.gitignore`.

I have an empty example file here just as an example. 

---

# ⚙️ Configuration

Configuration can be set directly at the top of:

```text
twitch-chat-tts.ps1
```

or through environment variables.

The important settings are:

| Setting                  | Description            |
| ------------------------ | ---------------------- |
| `CHAT_TTS_CLIENT_ID`     | Twitch Client ID       |
| `CHAT_TTS_CLIENT_SECRET` | Twitch Client Secret   |
| `CHAT_TTS_CHANNEL`       | Twitch channel to join |
| `CHAT_TTS_BOT_NICK`      | Bot username           |
| `FASTKOKO_API`           | FastKoko API base URL  |

The script also has several local configuration options for things like:

* Required followers
* Required subscribers
* Maximum message length
* Link blocking
* Emote handling
* Notification behavior
* Ignored bots
* TTS response format

Check the configuration section at the top of the script.

---

# 🏃 Running It

Clone the repository:

```bash
git clone https://github.com/naturallocogaming/twitch-chat-tts.git
cd twitch-chat-tts
```

Update the configuration variables, or set Environment Variables. 

Start PowerShell 7:

```bash
pwsh
```

Then run:

```powershell
./twitch-chat-tts.ps1
```

On first launch:

1. The bot starts.
2. Your browser opens.
3. Twitch asks you to authorize the application.
4. Twitch redirects back to `localhost:8080`.
5. The bot receives the authorization code.
6. The bot exchanges it for tokens.
7. Tokens are saved locally.
8. The bot connects to Twitch Chat.
9. **Chat starts talking.**

Hopefully.

---

# 🌎 Environment Variables

You can configure the bot using environment variables instead of editing the script.

### macOS / Linux

```bash
export CHAT_TTS_CLIENT_ID=your-client-id
export CHAT_TTS_CLIENT_SECRET=your-client-secret
export CHAT_TTS_CHANNEL=yourchannel
export CHAT_TTS_BOT_NICK=PSSpeakerBot
export FASTKOKO_API=http://127.0.0.1:48880
```

### PowerShell

```powershell
$env:CHAT_TTS_CLIENT_ID = "your-client-id"
$env:CHAT_TTS_CLIENT_SECRET = "your-client-secret"
$env:CHAT_TTS_CHANNEL = "yourchannel"
$env:CHAT_TTS_BOT_NICK = "PSSpeakerBot"
$env:FASTKOKO_API = "http://127.0.0.1:48880"
```

Then:

```powershell
./twitch-chat-tts.ps1
```

---

# 📁 Files

| File                  | What it does                           |
| --------------------- | -------------------------------------- |
| `twitch-chat-tts.ps1` | The actual bot                         |
| `UserVoices.csv`      | Persistent per-user voice preferences  |
| `BannedWords.txt`     | Moderation word list                   |
| `bot_token.json`      | Twitch OAuth tokens — **KEEP PRIVATE** |

---

# 🧪 Linting

Want to pretend this is a serious software project?

Install PSScriptAnalyzer:

```powershell
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser
```

Then:

```powershell
Invoke-ScriptAnalyzer -Path ./twitch-chat-tts.ps1
```

You can also use `Invoke-Formatter` or the PowerShell extension in VS Code to format the script.

Shoud you? ¯\\_(ツ)_/¯

---

# 🐛 Troubleshooting

### `Cannot resolve broadcaster`

Check:

* `CHAT_TTS_CHANNEL`
* Twitch OAuth credentials
* OAuth token validity

Make sure the channel name doesn't contain `#`.

### 🔇 No audio

Make sure one of these is installed and available in your `PATH`:

```text
ffplay
mpg123
afplay
```

On macOS, `afplay` should already be available.

### 🔐 OAuth doesn't work

Check that:

```text
http://localhost:8080/
```

is configured as the redirect URI in your Twitch application.

Also make sure port `8080` isn't already being used by something else.

### 🤖 Chat isn't being read

Check:

* Moderation settings
* `BannedWords.txt`
* Follower/subscriber restrictions
* Per-user cooldowns
* Whether the message is a Twitch redemption
* Whether the message contains a blocked link
* The console debug log

And remember:

**Sometimes it's not broken. Sometimes you told it to ignore the message.**

---

# 🏗️ Project Status

This project is **actively being developed** and is currently part of the Natural Loco streaming setup.

It started as:

> “I need a way to hear Twitch Chat when I get hyperfocused.”

It became:

> “I should build a Twitch IRC client.”

Which became:

> “I should add OAuth.”

Which became:

> “It needs a queue.”

Which became:

> “Chat should be able to choose their voice.”

Which became:

> “I need moderation.”

Which became:

> “Well, now it needs a UI.”

And that's how we got here.

There are absolutely more features planned.

I regret nothing.

---

# 🤝 Contributing

Found a bug?

Have an idea?

Want to make the architecture less stupid?

**Please do.**

Issues and pull requests are welcome.

If you improve something, I would genuinely love to see it.

If you discover that I've made a terrible architectural decision...

Please be gentle.

I'm sensitive.

---

# 📜 License

This project is released under the **MIT License**.

See [`LICENSE`](LICENSE) for the full license text.

---

# 🪇 About Natural Loco

I'm **Natural Loco**, an IT nerd and Twitch streamer who has somehow managed to turn playing video games into an excuse to build infrastructure.

I work with cloud platforms, automation, DevOps, systems architecture, and all sorts of other things that probably shouldn't be involved in a Twitch stream.

I also play games.

Sometimes Chat yells at me.

Sometimes I yell at Chat.

Now Chat can yell at me **with a voice.**

💻🪇⚡️

**Twitch:** `https://twitch.tv/naturalloco`

**GitHub:** `https://github.com/naturallocogaming`

**TikTok:** `https://www.tiktok.com/@natural.loco`

**Youtube:** `https://www.youtube.com/@NaturalLoco`

---

## 🎬 Built for a video

This project was originally created as part of a video about building a Twitch Chat TTS system from scratch with PowerShell.

If you're here because you watched the video:

**Hi.**

Thanks for checking out the code.

Yes, this is actually how I spend my free time.

No, I don't understand why either.

**K thanks bye.**
