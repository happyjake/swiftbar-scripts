#!/bin/bash

# <xbar.title>Streaming Service Status</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.author>Jake</xbar.author>
# <xbar.author.github>jake</xbar.author.github>
# <xbar.desc>Check availability of streaming services (YouTube, Netflix, Disney+, Dazn, Peacock, Roblox)</xbar.desc>
# <xbar.dependencies>bash,curl</xbar.dependencies>

# Cache file to store results
CACHE_FILE="/tmp/streaming-check-cache.json"
CACHE_MAX_AGE=1800  # 30 minutes in seconds
LOG_FILE="/tmp/streaming-check.log"

# User agents
UA_BROWSER="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
UA_SEC_CH_UA='"Google Chrome";v="125", "Chromium";v="125", "Not.A/Brand";v="24"'

# Timeout for curl operations
CURL_TIMEOUT=10

# Logging function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Generate a random string
gen_random_str() {
    LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$1"
}

# Check YouTube Premium availability
check_youtube() {
    local tmpresult=$(curl -sL --max-time $CURL_TIMEOUT 'https://www.youtube.com/premium' \
        -H 'accept-language: en-US,en;q=0.9' \
        --user-agent "${UA_BROWSER}" 2>/dev/null)

    if [ -z "$tmpresult" ]; then
        log_message "YouTube: Failed - No response"
        echo "Failed"
        return
    fi

    local isCN=$(echo "$tmpresult" | grep 'www.google.cn')
    if [ -n "$isCN" ]; then
        log_message "YouTube: No - Region: CN"
        echo "No|CN"
        return
    fi

    local isNotAvailable=$(echo "$tmpresult" | grep -i 'Premium is not available in your country')
    local region=$(echo "$tmpresult" | sed -n 's/.*"INNERTUBE_CONTEXT_GL"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
    local isAvailable=$(echo "$tmpresult" | grep -i 'ad-free')

    if [ -n "$isNotAvailable" ]; then
        log_message "YouTube: No"
        echo "No"
        return
    fi

    if [ -n "$isAvailable" ] && [ -n "$region" ]; then
        log_message "YouTube: Yes - Region: $region"
        echo "Yes|$region"
        return
    fi

    log_message "YouTube: Unknown"
    echo "Unknown"
}

# Check Netflix availability
check_netflix() {
    # LEGO Ninjago (Original content)
    local tmpresult1=$(curl -fsL --max-time $CURL_TIMEOUT 'https://www.netflix.com/title/81280792' \
        -H 'accept: text/html,application/xhtml+xml,application/xml;q=0.9' \
        -H 'accept-language: en-US,en;q=0.9' \
        --user-agent "${UA_BROWSER}" 2>/dev/null)

    # Breaking Bad (Licensed content)
    local tmpresult2=$(curl -fsL --max-time $CURL_TIMEOUT 'https://www.netflix.com/title/70143836' \
        -H 'accept: text/html,application/xhtml+xml,application/xml;q=0.9' \
        -H 'accept-language: en-US,en;q=0.9' \
        --user-agent "${UA_BROWSER}" 2>/dev/null)

    if [ -z "$tmpresult1" ] || [ -z "$tmpresult2" ]; then
        log_message "Netflix: Failed - No response"
        echo "Failed"
        return
    fi

    local result1=$(echo "$tmpresult1" | grep 'Oh no!')
    local result2=$(echo "$tmpresult2" | grep 'Oh no!')

    # Both blocked = Originals Only
    if [ -n "$result1" ] && [ -n "$result2" ]; then
        log_message "Netflix: Originals Only"
        echo "Originals"
        return
    fi

    # At least one available = Full access
    if [ -z "$result1" ] || [ -z "$result2" ]; then
        local region=$(echo "$tmpresult1" | grep -o 'data-country="[A-Z]*"' | sed 's/.*="\([A-Z]*\)"/\1/' | head -n1)
        if [ -n "$region" ]; then
            log_message "Netflix: Yes - Region: $region"
            echo "Yes|$region"
        else
            log_message "Netflix: Yes"
            echo "Yes"
        fi
        return
    fi

    log_message "Netflix: No"
    echo "No"
}

# Check Amazon Prime Video availability
check_primevideo() {
    local tmpresult=$(curl -sL --max-time $CURL_TIMEOUT 'https://www.primevideo.com' \
        --user-agent "${UA_BROWSER}" 2>/dev/null)

    if [ -z "$tmpresult" ]; then
        log_message "Prime Video: Failed - No response"
        echo "Failed"
        return
    fi

    local isBlocked=$(echo "$tmpresult" | grep -i 'isServiceRestricted')
    local region=$(echo "$tmpresult" | sed -n 's/.*"currentTerritory":"\([^"]*\)".*/\1/p' | head -n1)

    if [ -z "$isBlocked" ] && [ -z "$region" ]; then
        log_message "Prime Video: Failed - Page error"
        echo "Failed"
        return
    fi

    if [ -n "$isBlocked" ]; then
        log_message "Prime Video: No - Service not available"
        echo "No"
        return
    fi

    if [ -n "$region" ]; then
        log_message "Prime Video: Yes - Region: $region"
        echo "Yes|$region"
        return
    fi

    log_message "Prime Video: Failed - Unknown region"
    echo "Failed"
}

# Check Disney+ availability
check_disney() {
    local tempresult=$(curl -s --max-time $CURL_TIMEOUT 'https://disney.api.edge.bamgrid.com/devices' \
        -X POST \
        -H "authorization: Bearer ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84" \
        -H "content-type: application/json; charset=UTF-8" \
        -d '{"deviceFamily":"browser","applicationRuntime":"chrome","deviceProfile":"windows","attributes":{}}' \
        --user-agent "${UA_BROWSER}" 2>/dev/null)

    if [ -z "$tempresult" ]; then
        log_message "Disney+: Failed - No response"
        echo "Failed"
        return
    fi

    local is403=$(echo "$tempresult" | grep -i '403 ERROR')
    if [ -n "$is403" ]; then
        log_message "Disney+: No - IP banned"
        echo "No"
        return
    fi

    # Simplified check - just verify we can get a device token
    local assertion=$(echo "$tempresult" | sed -n 's/.*"assertion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    if [ -z "$assertion" ]; then
        log_message "Disney+: Failed - No assertion"
        echo "Failed"
        return
    fi

    # Try to get region info from disneyplus.com
    local previewcheck=$(curl -sL --max-time $CURL_TIMEOUT 'https://disneyplus.com' \
        -w '%{url_effective}\n' -o /dev/null --user-agent "${UA_BROWSER}" 2>/dev/null)
    local isUnavailable=$(echo "$previewcheck" | grep -E 'preview|unavailable')

    if [ -n "$isUnavailable" ]; then
        log_message "Disney+: No - Unavailable"
        echo "No"
        return
    fi

    # Get region from redirect
    local region=$(echo "$previewcheck" | grep -o 'disneyplus\.com/[a-z][a-z]-[a-z][a-z]' | head -n1 | cut -d'/' -f2 | cut -d'-' -f1 | tr '[:lower:]' '[:upper:]')

    if [ -n "$region" ]; then
        log_message "Disney+: Yes - Region: $region"
        echo "Yes|$region"
    else
        log_message "Disney+: Yes"
        echo "Yes"
    fi
}

# Check Dazn availability
check_dazn() {
    local tmpresult=$(curl -s --max-time $CURL_TIMEOUT 'https://startup.core.indazn.com/misl/v5/Startup' \
        -H 'accept: */*' \
        -H 'accept-language: en-US,en;q=0.9' \
        -H 'content-type: application/json' \
        -H 'origin: https://www.dazn.com' \
        -H 'referer: https://www.dazn.com/' \
        --data-raw '{"Version":"2","LandingPageKey":"generic","Languages":"en-US","Platform":"web","Manufacturer":"","PromoCode":"","PlatformAttributes":{}}' \
        --user-agent "${UA_BROWSER}" 2>/dev/null)

    if [ -z "$tmpresult" ]; then
        log_message "Dazn: Failed - No response"
        echo "Failed"
        return
    fi

    if echo "$tmpresult" | grep -qi "Security policy has been breached"; then
        log_message "Dazn: Banned - Security policy breached"
        echo "Banned"
        return
    fi

    local result=$(echo "$tmpresult" | sed -n 's/.*"isAllowed"[[:space:]]*:[[:space:]]*\(false\|true\).*/\1/p')
    local region=$(echo "$tmpresult" | sed -n 's/.*"GeolocatedCountry"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | tr '[:lower:]' '[:upper:]')

    case "$result" in
        'false')
            log_message "Dazn: No"
            echo "No"
            ;;
        'true')
            if [ -n "$region" ]; then
                log_message "Dazn: Yes - Region: $region"
                echo "Yes|$region"
            else
                log_message "Dazn: Yes"
                echo "Yes"
            fi
            ;;
        *)
            log_message "Dazn: Failed - Unknown result: $result"
            echo "Failed"
            ;;
    esac
}

# Check Peacock TV availability
check_peacock() {
    local tmpresult=$(curl -fsL --max-time $CURL_TIMEOUT 'https://www.peacocktv.com/' \
        -w '%{http_code}_TAG_%{url_effective}\n' -o /dev/null \
        --user-agent "${UA_BROWSER}" 2>/dev/null)

    local httpCode=$(echo "$tmpresult" | awk -F'_TAG_' '{print $1}')
    if [ "$httpCode" == '000' ]; then
        log_message "Peacock: Failed - No response"
        echo "Failed"
        return
    fi

    local urlEffective=$(echo "$tmpresult" | awk -F'_TAG_' '{print $2}')
    local result=$(echo "$urlEffective" | grep -i 'unavailable')

    if [ -n "$result" ]; then
        log_message "Peacock: No - Unavailable"
        echo "No"
        return
    fi

    if [ "$httpCode" == '200' ]; then
        log_message "Peacock: Yes - Region: US"
        echo "Yes|US"
        return
    fi

    log_message "Peacock: Failed - HTTP $httpCode"
    echo "Failed"
}

# Check ChatGPT availability
check_chatgpt() {
    local tmpresult=$(curl -sL --max-time $CURL_TIMEOUT 'https://chatgpt.com/' \
        -H 'accept: text/html,application/xhtml+xml,application/xml;q=0.9' \
        -H 'accept-language: en-US,en;q=0.9' \
        --user-agent "${UA_BROWSER}" 2>/dev/null)

    if [ -z "$tmpresult" ]; then
        log_message "ChatGPT: Failed - No response"
        echo "Failed"
        return
    fi

    # Check if we're getting the normal page (not blocked/unavailable)
    local isUnavailable=$(echo "$tmpresult" | grep -i 'not available\|unable to access')

    if [ -n "$isUnavailable" ]; then
        log_message "ChatGPT: No - Service unavailable"
        echo "No"
        return
    fi

    # If we get a valid response, consider it available
    local hasContent=$(echo "$tmpresult" | grep -i 'chatgpt\|openai')
    if [ -n "$hasContent" ]; then
        log_message "ChatGPT: Yes"
        echo "Yes"
        return
    fi

    log_message "ChatGPT: Unknown - Unexpected response"
    echo "Unknown"
}

# Check Google Gemini availability
check_gemini() {
    local tmpresult=$(curl -sL --max-time $CURL_TIMEOUT 'https://gemini.google.com/' \
        -H 'accept: text/html,application/xhtml+xml,application/xml;q=0.9' \
        -H 'accept-language: en-US,en;q=0.9' \
        --user-agent "${UA_BROWSER}" 2>/dev/null)

    if [ -z "$tmpresult" ]; then
        log_message "Gemini: Failed - No response"
        echo "Failed"
        return
    fi

    # Check for redirect to unavailable page
    local httpCode=$(curl -sL --max-time $CURL_TIMEOUT 'https://gemini.google.com/' \
        -w '%{http_code}' -o /dev/null \
        --user-agent "${UA_BROWSER}" 2>/dev/null)

    if [ "$httpCode" == "000" ]; then
        log_message "Gemini: Failed - Network error"
        echo "Failed"
        return
    fi

    # Check if blocked
    local isBlocked=$(echo "$tmpresult" | grep -i "isn't available\|not available in your")

    if [ -n "$isBlocked" ]; then
        log_message "Gemini: No - Not available in region"
        echo "No"
        return
    fi

    # Try to detect region from HTML
    local region=$(echo "$tmpresult" | sed -n 's/.*"gl":"\([A-Z][A-Z]\)".*/\1/p' | head -n1)

    if [ "$httpCode" == "200" ]; then
        if [ -n "$region" ]; then
            log_message "Gemini: Yes - Region: $region"
            echo "Yes|$region"
        else
            log_message "Gemini: Yes"
            echo "Yes"
        fi
        return
    fi

    log_message "Gemini: Unknown"
    echo "Unknown"
}

# Check Claude availability
check_claude() {
    local tmpresult=$(curl -sL --max-time $CURL_TIMEOUT 'https://claude.ai/' \
        -H 'accept: text/html,application/xhtml+xml,application/xml;q=0.9' \
        -H 'accept-language: en-US,en;q=0.9' \
        --user-agent "${UA_BROWSER}" 2>/dev/null)

    if [ -z "$tmpresult" ]; then
        log_message "Claude: Failed - No response"
        echo "Failed"
        return
    fi

    # Check if we're getting blocked
    local isBlocked=$(echo "$tmpresult" | grep -i 'not available\|access denied')

    if [ -n "$isBlocked" ]; then
        log_message "Claude: No - Service unavailable"
        echo "No"
        return
    fi

    # If we get Claude content, it's available
    local hasContent=$(echo "$tmpresult" | grep -i 'claude\|anthropic')
    if [ -n "$hasContent" ]; then
        log_message "Claude: Yes"
        echo "Yes"
        return
    fi

    log_message "Claude: Unknown - Unexpected response"
    echo "Unknown"
}

# Check MathsSpot Roblox availability
check_roblox() {
    local tmpresult=$(curl -sL --max-time $CURL_TIMEOUT 'https://mathsspot.com/' \
        -H 'accept: */*' \
        -H 'accept-language: en-US,en;q=0.9' \
        --user-agent "${UA_BROWSER}" 2>/dev/null)

    if [ -z "$tmpresult" ]; then
        log_message "Roblox: Failed - No response"
        echo "Failed"
        return
    fi

    local isBlocked=$(echo "$tmpresult" | grep -i 'FailureServiceNotInRegion')
    if [ -n "$isBlocked" ]; then
        log_message "Roblox: No - Not in region"
        echo "No"
        return
    fi

    local apiPath=$(echo "$tmpresult" | sed -n 's/.*fetch("\([^"]*\)".*/\1/p' | grep 'reportEvent' | sed 's/\/reportEvent//;s/^\///' | head -n1)
    local region=$(echo "$tmpresult" | sed -n 's/.*"countryCode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    local nggFeVersion=$(echo "$tmpresult" | sed -n 's/.*"NEXT_PUBLIC_FE_VERSION"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    if [ -z "$apiPath" ] || [ -z "$nggFeVersion" ]; then
        log_message "Roblox: Failed - Missing API path or version"
        echo "Failed"
        return
    fi

    # Generate fake IDs
    local fakeUAId=$(gen_random_str 21)
    local fakeSessId=$(gen_random_str 21)
    local fakeFesessId=$(gen_random_str 21)
    local fakeVisitId=$(gen_random_str 21)

    local tmpresult1=$(curl -sL --max-time $CURL_TIMEOUT \
        "https://mathsspot.com/${apiPath}/startSession?appId=5349&uaId=ua-${fakeUAId}&uaSessionId=uasess-${fakeSessId}&feSessionId=fesess-${fakeFesessId}&visitId=visitid-${fakeVisitId}&initialOrientation=landscape&utmSource=NA&utmMedium=NA&utmCampaign=NA&deepLinkUrl=&accessCode=&ngReferrer=NA&pageReferrer=NA&ngEntryPoint=https%3A%2F%2Fmathsspot.com%2F&ntmSource=NA&customData=&appLaunchExtraData=&feSessionTags=nowgg&sdpType=&eVar=&isIframe=false&feDeviceType=desktop&feOsName=window&userSource=direct&visitSource=direct&userCampaign=NA&visitCampaign=NA" \
        -H 'accept: */*' \
        -H 'accept-language: en-US,en;q=0.9' \
        -H 'referer: https://mathsspot.com/' \
        -H "sec-ch-ua: ${UA_SEC_CH_UA}" \
        -H 'sec-ch-ua-mobile: ?0' \
        -H 'sec-ch-ua-platform: "Windows"' \
        -H 'x-ngg-skip-evar-check: true' \
        -H "x-ngg-fe-version: ${nggFeVersion}" \
        --user-agent "${UA_BROWSER}" 2>/dev/null)

    if [ -z "$tmpresult1" ]; then
        log_message "Roblox: Failed - No API response"
        echo "Failed"
        return
    fi

    local status=$(echo "$tmpresult1" | sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)

    case "$status" in
        'FailureServiceNotInRegion')
            log_message "Roblox: No - Service not in region"
            echo "No"
            ;;
        'FailureProxyUserLimitExceeded')
            log_message "Roblox: No - Proxy/VPN detected"
            echo "No"
            ;;
        'Success')
            if [ -n "$region" ]; then
                log_message "Roblox: Yes - Region: $region"
                echo "Yes|$region"
            else
                log_message "Roblox: Yes"
                echo "Yes"
            fi
            ;;
        *)
            log_message "Roblox: Failed - Status: $status"
            echo "Failed"
            ;;
    esac
}

# Format status for display
format_status() {
    local service="$1"
    local status="$2"
    local service_key="$3"

    local icon=""
    local color=""
    local text=""

    IFS='|' read -r result region <<< "$status"

    case "$result" in
        "Yes")
            icon="✅"
            color="green"
            if [ -n "$region" ]; then
                text="$service: Yes (Region: $region)"
            else
                text="$service: Yes"
            fi
            ;;
        "No")
            icon="❌"
            color="red"
            text="$service: No"
            ;;
        "Originals")
            icon="⚠️"
            color="orange"
            text="$service: Originals Only"
            ;;
        "Banned")
            icon="🚫"
            color="red"
            text="$service: IP Banned"
            ;;
        "Failed"|"Unknown")
            icon="❓"
            color="gray"
            text="$service: Failed"
            ;;
        *)
            icon="❓"
            color="gray"
            text="$service: Unknown"
            ;;
    esac

    echo "$icon $text | color=$color refresh=true bash=\"$SCRIPT_PATH\" param1=refresh_service param2=$service_key terminal=false"
}

# Force refresh all
if [ "$1" == "refresh" ]; then
    rm -f "$CACHE_FILE"
    exit
fi

# Refresh individual service
if [ "$1" == "refresh_service" ]; then
    SERVICE="$2"

    # Load existing cache if it exists
    if [ -f "$CACHE_FILE" ]; then
        log_message "Refreshing $SERVICE..."

        # Run the specific check
        case "$SERVICE" in
            "youtube") NEW_STATUS=$(check_youtube) ;;
            "netflix") NEW_STATUS=$(check_netflix) ;;
            "primevideo") NEW_STATUS=$(check_primevideo) ;;
            "disney") NEW_STATUS=$(check_disney) ;;
            "peacock") NEW_STATUS=$(check_peacock) ;;
            "roblox") NEW_STATUS=$(check_roblox) ;;
            "chatgpt") NEW_STATUS=$(check_chatgpt) ;;
            "gemini") NEW_STATUS=$(check_gemini) ;;
            "claude") NEW_STATUS=$(check_claude) ;;
            *) exit ;;
        esac

        # Update cache with new status
        if command -v jq >/dev/null 2>&1; then
            # Use jq to update the specific field
            TMP_FILE=$(mktemp)
            jq --arg service "$SERVICE" --arg status "$NEW_STATUS" '.[$service] = $status' "$CACHE_FILE" > "$TMP_FILE"
            mv "$TMP_FILE" "$CACHE_FILE"
        else
            # Fallback: read all values, update one, rewrite
            YOUTUBE_STATUS=$(grep -o '"youtube"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/')
            NETFLIX_STATUS=$(grep -o '"netflix"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/')
            PRIMEVIDEO_STATUS=$(grep -o '"primevideo"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/')
            DISNEY_STATUS=$(grep -o '"disney"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/')
            PEACOCK_STATUS=$(grep -o '"peacock"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/')
            ROBLOX_STATUS=$(grep -o '"roblox"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/')
            CHATGPT_STATUS=$(grep -o '"chatgpt"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/')
            GEMINI_STATUS=$(grep -o '"gemini"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/')
            CLAUDE_STATUS=$(grep -o '"claude"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/')
            TIMESTAMP=$(grep -o '"timestamp"[[:space:]]*:[[:space:]]*[0-9]*' "$CACHE_FILE" | sed 's/.*:\s*\([0-9]*\).*/\1/')

            # Update the specific service
            case "$SERVICE" in
                "youtube") YOUTUBE_STATUS="$NEW_STATUS" ;;
                "netflix") NETFLIX_STATUS="$NEW_STATUS" ;;
                "primevideo") PRIMEVIDEO_STATUS="$NEW_STATUS" ;;
                "disney") DISNEY_STATUS="$NEW_STATUS" ;;
                "peacock") PEACOCK_STATUS="$NEW_STATUS" ;;
                "roblox") ROBLOX_STATUS="$NEW_STATUS" ;;
                "chatgpt") CHATGPT_STATUS="$NEW_STATUS" ;;
                "gemini") GEMINI_STATUS="$NEW_STATUS" ;;
                "claude") CLAUDE_STATUS="$NEW_STATUS" ;;
            esac

            # Rewrite cache
            cat > "$CACHE_FILE" <<EOF
{
  "youtube": "$YOUTUBE_STATUS",
  "netflix": "$NETFLIX_STATUS",
  "primevideo": "$PRIMEVIDEO_STATUS",
  "disney": "$DISNEY_STATUS",
  "peacock": "$PEACOCK_STATUS",
  "roblox": "$ROBLOX_STATUS",
  "chatgpt": "$CHATGPT_STATUS",
  "gemini": "$GEMINI_STATUS",
  "claude": "$CLAUDE_STATUS",
  "timestamp": $TIMESTAMP
}
EOF
        fi
    fi
    exit
fi

# View log file
if [ "$1" == "view_log" ]; then
    # Create log file if it doesn't exist
    [ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"
    open "$LOG_FILE"
    exit
fi

# Check if cache exists and is fresh
if [ -f "$CACHE_FILE" ]; then
    CACHE_AGE=$(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null)))
    if [ $CACHE_AGE -lt $CACHE_MAX_AGE ]; then
        USE_CACHE=1
    else
        USE_CACHE=0
    fi
else
    USE_CACHE=0
fi

# Run checks or use cache
if [ $USE_CACHE -eq 1 ]; then
    # Load from cache - check if jq is available
    if command -v jq >/dev/null 2>&1; then
        YOUTUBE_STATUS=$(jq -r '.youtube // "Unknown"' "$CACHE_FILE" 2>/dev/null)
        NETFLIX_STATUS=$(jq -r '.netflix // "Unknown"' "$CACHE_FILE" 2>/dev/null)
        PRIMEVIDEO_STATUS=$(jq -r '.primevideo // "Unknown"' "$CACHE_FILE" 2>/dev/null)
        DISNEY_STATUS=$(jq -r '.disney // "Unknown"' "$CACHE_FILE" 2>/dev/null)
        PEACOCK_STATUS=$(jq -r '.peacock // "Unknown"' "$CACHE_FILE" 2>/dev/null)
        ROBLOX_STATUS=$(jq -r '.roblox // "Unknown"' "$CACHE_FILE" 2>/dev/null)
        CHATGPT_STATUS=$(jq -r '.chatgpt // "Unknown"' "$CACHE_FILE" 2>/dev/null)
        GEMINI_STATUS=$(jq -r '.gemini // "Unknown"' "$CACHE_FILE" 2>/dev/null)
        CLAUDE_STATUS=$(jq -r '.claude // "Unknown"' "$CACHE_FILE" 2>/dev/null)
        LAST_CHECK=$(jq -r '.timestamp // 0' "$CACHE_FILE" 2>/dev/null)
    else
        # Fallback to grep/sed if jq not available
        YOUTUBE_STATUS=$(grep -o '"youtube"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/' || echo "Unknown")
        NETFLIX_STATUS=$(grep -o '"netflix"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/' || echo "Unknown")
        PRIMEVIDEO_STATUS=$(grep -o '"primevideo"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/' || echo "Unknown")
        DISNEY_STATUS=$(grep -o '"disney"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/' || echo "Unknown")
        PEACOCK_STATUS=$(grep -o '"peacock"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/' || echo "Unknown")
        ROBLOX_STATUS=$(grep -o '"roblox"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/' || echo "Unknown")
        CHATGPT_STATUS=$(grep -o '"chatgpt"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/' || echo "Unknown")
        GEMINI_STATUS=$(grep -o '"gemini"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/' || echo "Unknown")
        CLAUDE_STATUS=$(grep -o '"claude"[[:space:]]*:[[:space:]]*"[^"]*"' "$CACHE_FILE" | sed 's/.*":\s*"\([^"]*\)".*/\1/' || echo "Unknown")
        LAST_CHECK=$(grep -o '"timestamp"[[:space:]]*:[[:space:]]*[0-9]*' "$CACHE_FILE" | sed 's/.*:\s*\([0-9]*\).*/\1/' || echo "0")
    fi
else
    # Run checks
    log_message "=== Starting checks ==="
    YOUTUBE_STATUS=$(check_youtube)
    NETFLIX_STATUS=$(check_netflix)
    PRIMEVIDEO_STATUS=$(check_primevideo)
    DISNEY_STATUS=$(check_disney)
    PEACOCK_STATUS=$(check_peacock)
    ROBLOX_STATUS=$(check_roblox)
    CHATGPT_STATUS=$(check_chatgpt)
    GEMINI_STATUS=$(check_gemini)
    CLAUDE_STATUS=$(check_claude)
    LAST_CHECK=$(date +%s)
    log_message "=== Checks completed ==="

    # Save to cache (create JSON manually to avoid jq dependency for writing)
    cat > "$CACHE_FILE" <<EOF
{
  "youtube": "$YOUTUBE_STATUS",
  "netflix": "$NETFLIX_STATUS",
  "primevideo": "$PRIMEVIDEO_STATUS",
  "disney": "$DISNEY_STATUS",
  "peacock": "$PEACOCK_STATUS",
  "roblox": "$ROBLOX_STATUS",
  "chatgpt": "$CHATGPT_STATUS",
  "gemini": "$GEMINI_STATUS",
  "claude": "$CLAUDE_STATUS",
  "timestamp": $LAST_CHECK
}
EOF
fi

# Calculate time since last check
NOW=$(date +%s)
AGE=$((NOW - LAST_CHECK))
if [ $AGE -lt 60 ]; then
    TIME_AGO="now"
elif [ $AGE -lt 3600 ]; then
    TIME_AGO="$((AGE / 60))m ago"
else
    TIME_AGO="$((AGE / 3600))h ago"
fi

# Get script path
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# Menu bar display
echo "🪜"
echo "---"

# AI Services section
echo "🤖 AI Services | size=14 bash=\"$SCRIPT_PATH\" terminal=false"
format_status "ChatGPT" "$CHATGPT_STATUS" "chatgpt"
format_status "Google Gemini" "$GEMINI_STATUS" "gemini"
format_status "Claude" "$CLAUDE_STATUS" "claude"

echo "---"

# Multinational section
echo "🌍 Streaming Services | size=14 bash=\"$SCRIPT_PATH\" terminal=false"
format_status "YouTube Premium" "$YOUTUBE_STATUS" "youtube"
format_status "Netflix" "$NETFLIX_STATUS" "netflix"
format_status "Amazon Prime Video" "$PRIMEVIDEO_STATUS" "primevideo"
format_status "Disney+" "$DISNEY_STATUS" "disney"

echo "---"

# North America section
echo "🇺🇸 North America | size=14 bash=\"$SCRIPT_PATH\" terminal=false"
format_status "Peacock TV" "$PEACOCK_STATUS" "peacock"
format_status "MathsSpot Roblox" "$ROBLOX_STATUS" "roblox"

echo "---"
echo "🔄 Refresh All | bash=\"$SCRIPT_PATH\" param1=refresh terminal=false refresh=true"
echo "📋 View Logs | bash=\"$SCRIPT_PATH\" param1=view_log terminal=false"
echo "⏱️ Last check: $TIME_AGO | size=12 color=gray"
