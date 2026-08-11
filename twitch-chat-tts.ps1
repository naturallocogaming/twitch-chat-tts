<# ===============================
  Cross-Platform Twitch TTS Bot
  Features:
  - OAuth with token save/refresh
  - IRC chat commands: !myvoice, !voices, !setvoice, !refreshvoices
  - Moderation: ignore emotes, follower/subscriber restrictions, banned words, links
  - User voice preferences via CSV
  - FastKoko TTS API integration
  - Cross-platform audio playback
  - Queue system + per-user cooldown
  - Console UI controls: Pause (P), Stop (S), Skip (K), Show queue (Q)
=================================#>
$Host.UI.RawUI.WindowTitle = "ChatTTS"
# ------------ CONFIG ------------
$ClientId        = "REPLACEME"  # Replace with your Twitch app client ID
$ClientSecret    = "REPLACEME"  # Replace with your Twitch app client secret
$BotNick         = "PSSpeakerBot" # The bot's nickname (this is prepended to its notify messages in chat. e.g. "NaturalLoco: PSSpeakerBot: 💬 Chat, I'm here to read your messages! Commands: !myvoice, !voices, !setvoice <voice>")
$ChannelName     = "naturalloco" # The Twitch channel to join (without the #) Usually the same as the bot's owner. This is the channel where the bot will read messages aloud.
$ChannelTag      = "#$ChannelName"
$FastKokoAPI     = "http://192.168.1.225:48880" # The FastKoko TTS API endpoint (replace with your own)
$VoicesEndpoint  = "$FastKokoAPI/v1/audio/voices"
$TTSApiEndpoint  = "$FastKokoAPI/v1/audio/speech"
$ResponseFormat  = "mp3" #The audio format for TTS responses (e.g., "mp3", "wav", "ogg"). Ensure your audio player supports this format.
$UserVoiceFile   = "UserVoices.csv" #The CSV file to store user voice preferences. Format: Username,Voice. For larger channels, consider using a database or more efficient storage.
$TokenFile       = "bot_token.json" #The JSON file to store the Twitch OAuth token and refresh token. This allows the bot to maintain its session across restarts without requiring re-authentication.
$RedirectUri     = "http://localhost:8080/" # The redirect URI for Twitch OAuth. Must match the one set in your Twitch app settings. Ensure this port is free and accessible.
$IgnoredBots     = "nightbot","sery_bot" # List of bot usernames to ignore for follower/subscriber checks. Add any known bot usernames here to prevent them from being read aloud.
$IgnoreEmotes    = $false # Whether to ignore emotes in chat messages. Set to $true to remove emotes from messages before TTS processing.
$RequireFollower = $false # Whether to require users to be followers to have their messages read aloud. Set to $true to enforce this restriction.
$RequireSubscriber = $false # Whether to require users to be subscribers to have their messages read aloud. Set to $true to enforce this restriction.
$MaxMessageLength = 500 # Maximum length of chat messages to be read aloud. Messages longer than this will be ignored. Adjust based on your needs.
$BlockLinks      = $true # Whether to block messages containing links. Set to
$Scopes          = "chat:read chat:edit moderator:read:followers channel:read:subscriptions user:read:email" # The OAuth scopes required for the bot. Adjust based on your needs. Ensure these match the scopes requested during OAuth authorization.
$Global:NotifyEnabled = $false      # default off can toggle when running
$Global:NotifySchedule = 900       # seconds (15 min default)

# List of possible notify messages (can include emoji)
$NotifyMessages = @(
    "Hey chat! I can read messages aloud. Commands: !myvoice, !voices, !setvoice <voice>, !refreshvoices 🎤",
    "💬 I can read your messages aloud! Try !myvoice or !setvoice <voice>",
    "TTS Bot is online! Speak to me with chat commands 🎶",
    "Want your chat read out? Use !myvoice, !voices, !setvoice, !refreshvoices 🤖",
    "👋 Hello everyone! Want me to read your messages? Commands: !myvoice, !voices, !setvoice <voice>",
    "TTS bot online! 🔊 Ask me: !myvoice, !voices, !setvoice <voice>",
    "💬 Chat, I'm here to read your messages! Commands: !myvoice, !voices, !setvoice <voice>",
    "Ping! 📢 Let me speak your messages! Try: !myvoice, !voices, !setvoice <voice>",
    "Attention chat! 🎧 Use !myvoice, !voices, !setvoice <voice> to customize how I talk!"
)
$Global:DebugLog = New-Object System.Collections.Generic.List[string]
$Global:ShowDebug = $false



$Config = [ordered]@{
    IgnoreEmotes       = $IgnoreEmotes
    RequireFollower    = $RequireFollower
    RequireSubscriber  = $RequireSubscriber
    MaxMessageLength   = $MaxMessageLength
    BlockLinks         = $BlockLinks
    BannedWords        = @() # will populate below from a file. 
}

# Load banned words from external file (one word per line)
$BannedWordsFile = "BannedWords.txt"
if (Test-Path $BannedWordsFile) {
    $Config.BannedWords = Get-Content $BannedWordsFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
} else {
    # fallback default list if file missing
    $Config.BannedWords = @("slur1","slur2","slur3")
}

$CooldownSeconds = 5

# ------------ HELPERS ------------
function Save-Json($path, $obj) { ($obj | ConvertTo-Json -Depth 6) | Set-Content -Path $path -Encoding UTF8 }
function Import-Json($path) { if (Test-Path $path) { Get-Content $path -Raw | ConvertFrom-Json } else { $null } }

if (-not $Global:DebugLog) { $Global:DebugLog = [System.Collections.Generic.List[string]]::new() }

function Write-DebugLog {
    param([string]$Message)
    $timestamp = (Get-Date).ToString("HH:mm:ss")
    $entry = "[$timestamp] $Message"
    $Global:DebugLog.Add($entry)
    if ($Global:DebugLog.Count -gt 50) { $Global:DebugLog.RemoveAt(0) }
}



# ------------ OAUTH & TWITCH HELIX ------------
function Get-OAuthTokenInteractive {
    param(
        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [string]$ClientSecret,

        [Parameter(Mandatory)]
        [string]$RedirectUri,

        [Parameter(Mandatory)]
        [string]$Scopes,

        [int]$ListenerTimeoutSeconds = 10,

        [int]$TokenTimeoutSeconds = 30
    )

    $authUrl = "https://id.twitch.tv/oauth2/authorize" +
        "?client_id=$([uri]::EscapeDataString($ClientId))" +
        "&redirect_uri=$([uri]::EscapeDataString($RedirectUri))" +
        "&response_type=code" +
        "&scope=$([uri]::EscapeDataString($Scopes))"

    Write-Host "Opening Twitch authorization page..."
    Write-Host "Redirect URI: $RedirectUri"

    Start-Process $authUrl

    $listener = [System.Net.HttpListener]::new()

    try {
        # HttpListener requires a trailing slash
        if (-not $RedirectUri.EndsWith("/")) {
            throw "RedirectUri must end with '/'. Example: http://localhost:8080/"
        }

        $listener.Prefixes.Add($RedirectUri)
        $listener.Start()

        Write-Host "Waiting for Twitch OAuth callback..."
        Write-Host "Timeout: $ListenerTimeoutSeconds seconds"

        # IMPORTANT:
        # Don't use GetContext() because it blocks forever.
        $asyncResult = $listener.BeginGetContext($null, $null)

        if (-not $asyncResult.AsyncWaitHandle.WaitOne(
                [TimeSpan]::FromSeconds($ListenerTimeoutSeconds)
            )) {

            throw "Timed out waiting for Twitch OAuth callback."
        }

        $context = $listener.EndGetContext($asyncResult)

        $request = $context.Request
        $response = $context.Response

        Write-Host "OAuth callback received."

        # Check for Twitch OAuth errors first
        $error = $request.QueryString["error"]
        $errorDescription = $request.QueryString["error_description"]

        if ($error) {
            $message = "OAuth failed: $error`n$errorDescription"

            $response.StatusCode = 400
            $buf = [Text.Encoding]::UTF8.GetBytes($message)
            $response.ContentLength64 = $buf.Length
            $response.OutputStream.Write($buf, 0, $buf.Length)
            $response.OutputStream.Close()

            throw "Twitch OAuth failed: $error - $errorDescription"
        }

        $code = $request.QueryString["code"]

        if (-not $code) {
            $message = "No authorization code received."

            $response.StatusCode = 400
            $buf = [Text.Encoding]::UTF8.GetBytes($message)
            $response.ContentLength64 = $buf.Length
            $response.OutputStream.Write($buf, 0, $buf.Length)
            $response.OutputStream.Close()

            throw "No authorization code received."
        }

        # Tell the browser we're done
        $msg = "Authentication successful. You may close this window."
        $buf = [Text.Encoding]::UTF8.GetBytes($msg)

        $response.StatusCode = 200
        $response.ContentType = "text/plain"
        $response.ContentLength64 = $buf.Length
        $response.OutputStream.Write($buf, 0, $buf.Length)
        $response.OutputStream.Close()

        Write-Host "Authorization code received."

    }
    finally {
        if ($listener.IsListening) {
            $listener.Stop()
        }

        $listener.Close()
    }

    # Exchange authorization code for token
    Write-Host "Exchanging authorization code for Twitch token..."

    $tokenUrl = "https://id.twitch.tv/oauth2/token"

    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        code          = $code
        grant_type    = "authorization_code"
        redirect_uri  = $RedirectUri
    }

    try {
        $result = Invoke-RestMethod `
            -Method Post `
            -Uri $tokenUrl `
            -Body $body `
            -ContentType "application/x-www-form-urlencoded" `
            -TimeoutSec $TokenTimeoutSeconds `
            -ErrorAction Stop

        if (-not $result.access_token) {
            throw "Twitch returned a response without an access_token."
        }

        Write-Host "Successfully authenticated with Twitch."

        return $result
    }
    catch {
        Write-Error "Twitch token exchange failed:"
        Write-Error $_.Exception.Message

        # PowerShell sometimes hides the useful HTTP response.
        if ($_.ErrorDetails.Message) {
            Write-Error "Twitch response:"
            Write-Error $_.ErrorDetails.Message
        }

        throw
    }
}
function Update-OAuthToken {
  param([string]$ClientId, [string]$ClientSecret, [string]$RefreshToken)
  $tokenUrl = "https://id.twitch.tv/oauth2/token"
  $body = @{
    client_id     = $ClientId
    client_secret = $ClientSecret
    grant_type    = "refresh_token"
    refresh_token = $RefreshToken
  }
  Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body
}
function Test-AccessToken {
  $tok = Import-Json $TokenFile
  if ($tok -and $tok.access_token) {
    try {
      $newTok = Update-OAuthToken -ClientId $ClientId -ClientSecret $ClientSecret -RefreshToken $tok.refresh_token
      Save-Json $TokenFile $newTok
      return $newTok
    } catch {
      Write-Warning "Refresh failed, falling back to interactive auth… $_"
    }
  }
  $fresh = Get-OAuthTokenInteractive -ClientId $ClientId -ClientSecret $ClientSecret -RedirectUri $RedirectUri -Scopes $Scopes
  Save-Json $TokenFile $fresh
  return $fresh
}

$Token = Test-AccessToken
$Bearer = $Token.access_token
$OAuthForIRC = "oauth:$Bearer"
$HelixHeaders = @{ "Client-Id"=$ClientId; "Authorization"="Bearer $Bearer" }

function Get-UserByLogin([string]$login) { Invoke-RestMethod -Headers $HelixHeaders -Uri "https://api.twitch.tv/helix/users?login=$login" -Method Get }
function Get-MyUser() { Invoke-RestMethod -Headers $HelixHeaders -Uri "https://api.twitch.tv/helix/users" -Method Get }

$Broadcaster = (Get-UserByLogin $ChannelName).data | Select-Object -First 1
if (-not $Broadcaster) { throw "Cannot resolve broadcaster '$ChannelName'." }
$BroadcasterId = $Broadcaster.id

# ------------ VOICES & USER PREFS ------------
function Get-AvailableVoices { try { $resp = Invoke-RestMethod -Uri $VoicesEndpoint -Method Get; return $resp.voices | Where-Object { $_ -match '^[ab]' } } catch { @("af_bella") } }
function Get-UserVoices { if (-not (Test-Path $UserVoiceFile)) { return @{} }; $ht=@{}; foreach ($row in Import-Csv $UserVoiceFile) { if ($row.Voice) { $ht[$row.Username.ToLower()]=$row.Voice } }; $ht }
function Save-UserVoice($username,$voice) { 
    $rows=@(); 
    if (Test-Path $UserVoiceFile) { $rows=Import-Csv $UserVoiceFile | Where-Object { $_.Username.ToLower() -ne $username.ToLower() } } 
    $rows+=[pscustomobject]@{ Username=$username; Voice=$voice }; 
    $rows | Export-Csv $UserVoiceFile -NoTypeInformation 
}

$AvailableVoices = Get-AvailableVoices
if (-not $AvailableVoices -or $AvailableVoices.Count -eq 0) { $AvailableVoices = @("af_bella") }
$UserVoicePrefs = Get-UserVoices

# ------------ EMOTE STRIP & MODERATION ------------
function Remove-EmotesUsingRanges([string]$message, [string]$emotesTag) {
  if ([string]::IsNullOrEmpty($emotesTag)) { return $message }
  $chars = $message.ToCharArray()
  $remove = New-Object bool[] $chars.Length
  foreach ($def in $emotesTag.Split("/")) {
    if ($def -match "^\d+:(.+)$") {
      $ranges = $Matches[1].Split(",")
      foreach ($r in $ranges) { $pair=$r.Split("-"); for ($i=[int]$pair[0];$i -le [int]$pair[1];$i++) { if ($i -lt $remove.Length) {$remove[$i]=$true} } }
    }
  }
  $sb = New-Object System.Text.StringBuilder
  for ($i=0;$i -lt $chars.Length;$i++) { if (-not $remove[$i]) { [void]$sb.Append($chars[$i]) } }
  ($sb.ToString()).Trim()
}
function Test-AllowedByContent([string]$msg) {
    $low = $msg.ToLower()

    # Check max length
    if ($Config.MaxMessageLength -and $msg.Length -gt $Config.MaxMessageLength) {
        Write-DebugLog "Blocked message (too long): '$msg'"
        return $false
    }

    # Check for links
    if ($Config.BlockLinks -and ($msg -match "https?://|www\.")) {
        Write-DebugLog "Blocked message (link detected): '$msg'"
        return $false
    }

    foreach ($w in $Config.BannedWords) {
        if ($w -and $low -match "\b$([regex]::Escape($w))\b") {
            Write-DebugLog "Blocked message (banned word '$w'): '$msg'"
            return $false
        }
    }


    return $true
}
# --- Helper: Send Notify Message ---
function Send-NotifyMessage {
    try {
        # pick a random message
        $msg = $NotifyMessages | Get-Random
        Send-Chat $msg
        Write-DebugLog("Notify message sent: $msg")
    } catch {
        Write-DebugLog("Failed to send notify message: $($_.Exception.Message)")
    }
}


$FollowerCache=@{}; $SubscriberCache=@{}; $CacheTTL=[TimeSpan]::FromMinutes(5)
function Test-Cache($cache,$key) { if ($cache.ContainsKey($key)) { $entry=$cache[$key]; if ((Get-Date)-$entry.ts -lt $CacheTTL) { return $entry.allowed } $cache.Remove($key)|Out-Null }; $null }
function Test-Follower([string]$userId) { $cached=Test-Cache $FollowerCache $userId; if ($null -ne $cached){return $cached}; try { $resp=Invoke-RestMethod -Headers $HelixHeaders -Uri "https://api.twitch.tv/helix/channels/followers?broadcaster_id=$BroadcasterId&user_id=$userId" -Method Get; $isFollower=($resp.total -gt 0) } catch { $isFollower=$false }; $FollowerCache[$userId]=@{allowed=$isFollower;ts=Get-Date}; $isFollower }
function Test-Subscriber([string]$userId) { $cached=Test-Cache $SubscriberCache $userId; if ($null -ne $cached){return $cached}; try { $resp=Invoke-RestMethod -Headers $HelixHeaders -Uri "https://api.twitch.tv/helix/subscriptions?broadcaster_id=$BroadcasterId&user_id=$userId" -Method Get; $isSub=($resp.data.Count -gt 0) } catch { $isSub=$false }; $SubscriberCache[$userId]=@{allowed=$isSub;ts=Get-Date}; $isSub }
function Test-IgnoredBot([string]$userId) { $IgnoredBots.Contains($userId) }
function Test-AudienceRules([string]$userLogin) { $u=(Get-UserByLogin $userLogin).data | Select-Object -First 1; if (-not $u) { return $false }; if ($Config.RequireFollower -and -not (Test-Follower $u.id)) { return $false }; if ($Config.RequireSubscriber -and -not (Test-Subscriber $u.id)) { return $false }; if ((Test-IgnoredBot $userLogin) -eq $true) { return $false }; return $true }


# ------------ AUDIO PLAYBACK ------------
function Invoke-AudioFile($file) {
    return Start-Job -ScriptBlock {
        param($file)
        if ($IsWindows) {
            try {
                if (Get-Command ffplay -ErrorAction SilentlyContinue) {
                    ffplay -nodisp -autoexit $file
                } else {
                    $player = New-Object System.Media.SoundPlayer $file
                    $player.PlaySync()
                }
            } catch {
                Write-DebugLog "⚠️ Failed to play audio file: $file"
            }
        } elseif ($IsMacOS) { & afplay $file }
        else { 
            if (Get-Command mpg123 -ErrorAction SilentlyContinue) { & mpg123 $file } 
            elseif (Get-Command ffplay -ErrorAction SilentlyContinue) { & ffplay -nodisp -autoexit $file }
        }
    } -ArgumentList $file
}

# ------------ TTS ------------
function Invoke-TTS([string]$user,[string]$text,[string]$voice) { 
    $ttsText = "$user says: $text"
    $out=[IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), ".$ResponseFormat")
    try {
        $body=@{ input=$ttsText; voice=$voice; response_format=$ResponseFormat } | ConvertTo-Json
        Invoke-RestMethod -Uri $TTSApiEndpoint -Method Post -Body $body -ContentType "application/json" -OutFile $out | Out-Null
        $out
    } catch { Write-Warning "TTS failed: $_"; $null }
}

# ------------ IRC CONNECT ------------
$tcp = New-Object Net.Sockets.TcpClient "irc.chat.twitch.tv", 6667
$stream = $tcp.GetStream()
$reader = New-Object IO.StreamReader($stream)
$writer = New-Object IO.StreamWriter($stream); $writer.AutoFlush = $true
$writer.WriteLine("CAP REQ :twitch.tv/tags twitch.tv/commands")
$writer.WriteLine("PASS $OAuthForIRC")
$writer.WriteLine("NICK $BotNick")
$writer.WriteLine("JOIN $ChannelTag")
function Send-Chat($msg) { $writer.WriteLine("PRIVMSG $ChannelTag `:$BotNick`: $msg") }

# ------------ QUEUE & COOLDOWN ------------
$MessageQueue=[System.Collections.Concurrent.ConcurrentQueue[PSCustomObject]]::new()
$CurrentPlaying=$null
$CurrentJob = $null
$QueuePaused=$false
$UserCooldowns=@{}

function Add-MessageQueue {
    param([string]$user, [string]$text, [string]$voice)

    $now = Get-Date
    if ($UserCooldowns.ContainsKey($user)) {
        $lastTime = $UserCooldowns[$user]
        if (($now - $lastTime).TotalSeconds -lt $CooldownSeconds) {
            Write-DebugLog "Skipped message from $user due to cooldown: $text"
            return
        }
    }

    # Update cooldown
    $UserCooldowns[$user] = $now

    # Enqueue message
    try {
        $MessageQueue.Enqueue([pscustomobject]@{User=$user; Text=$text; Voice=$voice; Timestamp=$now})
        Write-DebugLog "Enqueued message from $user`: $text"
    } catch {
        Write-DebugLog "Failed to enqueue message from $user`: $($_.Exception.Message)"
    }
}


# ------------ MAIN LOOP (UI + IRC + QUEUE) ------------
$Running = $true

while ($Running) {
    # --- IRC message processing ---
    while ($stream.DataAvailable) {
        $line = $reader.ReadLine()
        if ($line.StartsWith("PING")) { 
            $writer.WriteLine($line.Replace("PING","PONG")); 
            continue 
        }

        if ($line -match "^@(.+?) :(\w+)!\w+@\w+\.tmi\.twitch\.tv PRIVMSG #\w+ :(.+)$") {
            $tagsStr=$Matches[1]; $user=$Matches[2]; $msg=$Matches[3]
            $tags=@{}; foreach($kv in $tagsStr.Split(";")){ $split=$kv.Split("="); $tags[$split[0]]=$split[1] }

            # new: ignore channel points reward redemptions (text/redemptions)
            if ($tags.ContainsKey("custom-reward-id") -and $tags["custom-reward-id"]) {
                Write-DebugLog "Skipped redemption from $user ($($tags["custom-reward-name"]))"
                continue
            }

            if ($Config.IgnoreEmotes){ $msg = Remove-EmotesUsingRanges $msg $tags.emotes }
            if (-not (Test-AllowedByContent $msg)){ continue }
            if (-not (Test-AudienceRules $user)){ continue }
            if ([string]::IsNullOrWhiteSpace($msg)) { Write-DebugLog "Skipped message from $user`: only emotes" ; continue }

            # Commands
            if ($msg -match "^!myvoice$"){ $v = $UserVoicePrefs[$($user.ToLower())]; Send-Chat("Your voice: $($v)"); continue }
            elseif ($msg -match "^!voices$"){ Send-Chat("Available voices: $($AvailableVoices -join ', ')"); continue }
            elseif ($msg -match "^!setvoice (\w+)$"){ 
                $v=$Matches[1]
                if ($AvailableVoices -contains $v){ Save-UserVoice $user $v; $UserVoicePrefs[$($user.ToLower())]=$v; $AvailableVoices = Get-AvailableVoices; Send-Chat("Voice for $user set to $v") }
                else { Send-Chat("Voice $v not available") }
                continue
            }
            elseif ($msg -match "^!refreshvoices$"){ $AvailableVoices = Get-AvailableVoices; Send-Chat("Voices refreshed: $($AvailableVoices -join ', ')"); continue }

            # Queue message
            $voice = $UserVoicePrefs[$($user.ToLower())]; if (-not $voice){$voice = $AvailableVoices | Get-Random}
            try {
                $MessageQueue.Enqueue([pscustomobject]@{User=$user; Text=$msg; Voice=$voice; Timestamp=Get-Date})
                [console]::beep()
            } catch {
                Write-DebugLog("Failed to enqueue message: $($_.Exception.Message)")
            }
        }
    }

    # --- Chat notify message processing ---
    if (-not $lastNotifyTime) {
    $lastNotifyTime = (Get-Date).AddSeconds(-$Global:NotifySchedule)
    }

    if ($Global:NotifyEnabled -and ((Get-Date) - $lastNotifyTime).TotalSeconds -ge $Global:NotifySchedule) {
        Send-NotifyMessage
        $lastNotifyTime = Get-Date
    }

# --- Autoplay next message ---
if (-not $QueuePaused -and -not $MessageQueue.IsEmpty -and -not $CurrentPlaying) {
    if ($MessageQueue.TryDequeue([ref]$msg)) {
        $CurrentPlaying = $msg
        try {
            $file = Invoke-TTS $msg.User $msg.Text $msg.Voice
            if ($file) { $CurrentJob = Invoke-AudioFile $file }
        } catch {
            Write-DebugLog "Autoplay failed for '$($msg.Text)': $($_.Exception.Message)"
            $CurrentPlaying = $null
        }
    }
}

# --- Check if current job finished ---
if ($CurrentJob) {
    if ($CurrentJob.State -eq 'Completed' -or $CurrentJob.State -eq 'Failed') {
        Remove-Job $CurrentJob -Force | Out-Null
        $CurrentJob = $null
        $CurrentPlaying = $null
    }
}

    # --- UI REFRESH ---
    Clear-Host
    Write-Host "==== Twitch TTS Bot ====" -ForegroundColor Cyan

    Write-Host "--- Status ---" -ForegroundColor White

    # TTS status
    Write-Host -NoNewline "[TTS] "
    if ($Global:IsPaused) {
        Write-Host "PAUSED" -ForegroundColor Yellow
    } else {
        Write-Host "RUNNING" -ForegroundColor Green
    }

    # Autoplay / Queue status
    Write-Host -NoNewline "[Autoplay] "
    if ($QueuePaused) { Write-Host "PAUSED" -ForegroundColor Yellow }
    else { Write-Host "RUNNING" -ForegroundColor Green }

    # Queue count
    Write-Host "[Queue: $($MessageQueue.Count)]" -ForegroundColor Cyan

    # Notify status
    Write-Host -NoNewline "[Notify] "
    if ($Global:NotifyEnabled) {
        Write-Host "ON" -ForegroundColor Green
    } else {
        Write-Host "OFF" -ForegroundColor Red
    }

    # Now Playing
    if ($CurrentPlaying) {
        Write-Host "Now Playing: $($CurrentPlaying.User): $($CurrentPlaying.Text)" -ForegroundColor Magenta
    } else {
        Write-Host "Now Playing: (none)" -ForegroundColor DarkGray
    }



    Write-Host "`n--- Message Queue ---" -ForegroundColor White
    if ($MessageQueue.Count -eq 0) {
        Write-Host "(empty)" -ForegroundColor DarkGray
    } else {
        $i = 1
        foreach ($msg in $MessageQueue.ToArray()[0..([Math]::Min($MessageQueue.Count-1,9))]) {
            Write-Host ("[$i] {0}: {1}" -f $msg.User, $msg.Text) -ForegroundColor Gray
            $i++
        }
        if ($MessageQueue.Count -gt 10) {
            Write-Host "... ($($MessageQueue.Count) total)" -ForegroundColor DarkGray
        }
    }

    Write-Host "`n--- Debug Log ---" -ForegroundColor White
    $Global:DebugLog | Select-Object -Last 5 | ForEach-Object {
    Write-Host $_ -ForegroundColor DarkRed
    }


    Write-Host "`n--- Controls ---" -ForegroundColor White

    Write-Host -NoNewline "["
    Write-Host -NoNewline "N" -ForegroundColor DarkCyan
    Write-Host -NoNewline "] Toggle Notify   ["

    Write-Host -NoNewline "L" -ForegroundColor Blue
    Write-Host "] Post Notify Now"

    Write-Host -NoNewline "["
    Write-Host -NoNewline "Enter" -ForegroundColor Green
    Write-Host -NoNewline "] Play next   ["

    Write-Host -NoNewline "K" -ForegroundColor Red
    Write-Host -NoNewline "] Skip   ["

    # Write-Host -NoNewline "I" -ForegroundColor DarkYellow
    # Write-Host -NoNewline "] Interrupt Current   ["

    Write-Host -NoNewline "P" -ForegroundColor Yellow
    Write-Host -NoNewline "] Pause/Resume   ["

    Write-Host -NoNewline "S" -ForegroundColor Magenta
    Write-Host -NoNewline "] Stop/Clear   ["

    Write-Host -NoNewline "D" -ForegroundColor DarkRed
    Write-Host -NoNewline "] Toggle Debug Log   ["

    Write-Host -NoNewline "E" -ForegroundColor Cyan
    Write-Host -NoNewline "] Exit"



    # --- Console input ---
    if ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'N'   {$Global:NotifyEnabled = -not $Global:NotifyEnabled}
            'L'   {Send-NotifyMessage}
            'P'   { $QueuePaused = -not $QueuePaused }
            'S'   { while ($MessageQueue.TryDequeue([ref]$null)){}; $QueuePaused = $true }
            'K'   { if ($CurrentJob) { try { Stop-Job $CurrentJob -Force ; Remove-Job $CurrentJob -Force } catch {} ; $CurrentJob = $null ; $CurrentPlaying = $null ; Write-DebugLog "Current TTS message interrupted by user." } }
            # 'I'   { if ($CurrentJob -and $Global:InterruptCurrent) { try { Stop-Job $CurrentJob -Force; Remove-Job $CurrentJob -Force } catch {} ; $CurrentJob = $null ; $CurrentPlaying = $null } }
            'D'   { $Global:ShowDebug = -not $Global:ShowDebug }
            'E'   { $Running = $false; $writer.WriteLine("QUIT"); $tcp.Close(); break }
            'Enter' {
                if (-not $MessageQueue.IsEmpty -and -not $CurrentPlaying) {
                    if ($MessageQueue.TryDequeue([ref]$msg)) {
                        $CurrentPlaying = $msg
                        $file = Invoke-TTS $msg.User $msg.Text $msg.Voice
                        if ($file) { $CurrentJob = Invoke-AudioFile $file }
                    }
                }
            }
        }
    }

    Start-Sleep -Milliseconds 200
}
