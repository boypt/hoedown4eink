

package.path = "common/?.lua;frontend/?.lua;plugins/exporter.koplugin/?.lua;" .. package.path
package.cpath = "common/?.so;common/?.dll;/usr/lib/lua/?.so;" .. package.cpath
require("ffi/loadlib")

-- Required libraries
local socket = require("socket")
local http = require("socket.http") -- Changed from 'https' to 'socket.http'
local ltn12 = require("ltn12")
local json = require("rapidjson") -- Using rapidjson as per original request
local IO = require("io") -- For file operations
local logger = require("logger")

-- Configuration (HARDCODED - PLEASE CHANGE THESE!)
-- Replace with the actual GitHub repository owner and name
local GITHUB_REPO_OWNER = "boypt"   -- Example: "luarocks"
local GITHUB_REPO_NAME = "hoedown4eink"      -- Example: "luarocks-luarocks"

-- Function to make an HTTP(S) GET request using socket.http and ltn12
-- Returns body (as string), status_code, or nil, error_message
local function http_get_api(url)
    local response_body_table = {}
    local success, status_code, headers, status_line = pcall(function()
        return socket.skip(1, http.request {
            url = url,
            headers = {
                -- GitHub API requires a specific Accept header for V3
                ["Accept"] = "application/vnd.github.v3+json",
                -- GitHub also recommends a User-Agent header
                ["User-Agent"] = "Lua-GitHub-Downloader/1.0 (https://github.com/<your_github_username>/<your_script_repo>)"
            },
            sink = ltn12.sink.table(response_body_table)
        })
    end)

    if not success then
        return nil, string.format("HTTP request failed: %s", tostring(status_code)) -- status_code here is the error msg
    end

    local body_string = table.concat(response_body_table)

    if not status_code then
        -- This can happen if the request itself failed before getting a status code
        return nil, "No status code received, possibly network error or non-existent host."
    end

    return body_string, status_code
end

-- Function to download a file from a URL, streaming it directly to a file
-- to avoid high memory usage.
-- Returns true on success, nil, error_message on failure
local function download_file(url, filename)
    print(string.format("Attempting to download from '%s' to '%s'", url, filename))

    local file_handle, err_open = IO.open(filename, "wb")
    if not file_handle then
        return nil, "Failed to open file for writing: " .. filename .. " - " .. tostring(err_open)
    end

    -- Use a protected call to ensure the file handle is closed even if the request fails
    local ok, status_code, headers, status_line = pcall(function()
        return socket.skip(1, http.request {
            url = url,
            headers = {
                ["User-Agent"] = "Lua-GitHub-Downloader/1.0 (https://github.com/<your_github_username>/<your_script_repo>)"
            },
            sink = ltn12.sink.file(file_handle)
        })
    end)
    -- file_handle is closed by sink.file already

    if not ok then
        os.remove(filename) -- Cleanup partial file on request error
        return nil, string.format("HTTP request for file failed: %s", tostring(status_code)) -- status_code is the error message
    end

    if not status_code then
        os.remove(filename) -- Cleanup
        return nil, "No status code received for file download."
    end

    if status_code >= 400 then
        os.remove(filename) -- Cleanup file that might contain an error message
        return nil, string.format("Failed to download file: Server responded with status %s for %s", status_code, url)
    end

    print(string.format("Successfully downloaded file to '%s'.", filename))
    return true
end


-- Main script execution
local args = {...} -- Get command line arguments

if #args < 1 then
    print("Usage: luajit gethoedown.lua <device_tag>")
    print("  Example: luajit gethoedown.lua kobo")
    print("  See project README for a list of available device tags (e.g., kobo, kindlepw2, x86_64).")
    os.exit(1)
end

local asset_name_to_match = args[1]
print(string.format("Looking for asset: '%s'", asset_name_to_match))

local latest_release_api_url = string.format(
    "https://api.github.com/repos/%s/%s/releases/latest",
    GITHUB_REPO_OWNER,
    GITHUB_REPO_NAME
)

print("\nFetching latest release information from:")
print(latest_release_api_url)

local release_body, release_status = http_get_api(latest_release_api_url)

if not release_body then
    print("Error: Could not retrieve latest release information. " .. tostring(release_status))
    os.exit(1)
end

if release_status ~= 200 then
    print(string.format("Error: GitHub API responded with status %d for %s", release_status, latest_release_api_url))
    print("Response body (if any):")
    -- Print only if body is not too large for an error message or if it looks like an error JSON
    if #release_body < 500 then
        print(release_body)
    else
        print(release_body:sub(1, 500) .. "...")
    end
    os.exit(1)
end

local ok, release_data = pcall(json.decode, release_body)

if not ok then
    print("Error: Failed to parse JSON response from GitHub API: " .. tostring(json_err))
    -- print the problematic body for debugging if it's not too long
    if #release_body < 500 then
        print("Problematic JSON body:")
        print(release_body)
    end
    os.exit(1)
end

if not release_data.assets or #release_data.assets == 0 then
    print("Error: No assets found in the latest release.")
    os.exit(1)
end

local found_asset = nil
for _, asset in ipairs(release_data.assets) do
    if asset.name:find(asset_name_to_match) then
        found_asset = asset
        break
    end
end

if found_asset then
    print(string.format("\nFound matching asset: %s (ID: %d)", found_asset.name, found_asset.id))
    print("Download URL: " .. found_asset.browser_download_url)

    local success, err = download_file(found_asset.browser_download_url, found_asset.name)
    if not success then
        print("Error: " .. tostring(err))
        os.exit(1)
    end
    os.execute(string.format("tar xvzf %s -C ./plugins/assistant.koplugin", found_asset.name))
    os.remove(found_asset.name)
else
    print(string.format("Error: Asset '%s' not found in the latest release.", asset_name_to_match))
    print("Available assets:")
    for _, asset in ipairs(release_data.assets) do
        print("  - " .. asset.name)
    end
    os.exit(1)
end

os.exit(0) -- Success
