#!/bin/bash
# Build the riff mattermost server and webapp
# which are in ~/go/src/github.com/mattermost/mattermost-server/
# and ~/go/src/github.com/mattermost/mattermost-webapp/

# Function to generate a random salt
# copied from mattermost-docker/app/entrypoint.sh -mjl
generate_salt() {
  tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 48 | head -n 1
}

DB_DOMAIN=${DB_DOMAIN:-edu-mm-db}
DB_PORT=${DB_PORT:-3306}

MM_USER="${MM_USER:-mmuser}"

MM_SERVER_REF=${MM_SERVER_REF:-develop}
MM_WEBAPP_REF=${MM_WEBAPP_REF:-develop}

DIST_ROOT=/home/${MM_USER}/riffedu
DIST_PATH=${DIST_ROOT}
BUILD_WEBAPP_DIR=../mattermost-webapp

# Create the parent directory for the mattermost server and webapp working directories
echo Cloning mm-server#$MM_SERVER_REF and mm-webapp#$MM_WEBAPP_REF
mkdir -p /home/${MM_USER}/go/src/github.com/mattermost

# Clone the RiffEdu mattermost server & webapp repos at the specified tag (git reference)
pushd /home/${MM_USER}/go/src/github.com/mattermost
git clone --depth 1 --branch $MM_SERVER_REF https://github.com/rifflearning/mattermost-server.git
git clone --depth 1 --branch $MM_WEBAPP_REF https://github.com/rifflearning/mattermost-webapp.git

# Build the server and client
pushd mattermost-server

# Set by the mattermost-server Makefile, used in build/release.mk and needed here
# for the packaging steps extracted from release.mk
export GOBIN=${PWD}/bin

make build-linux build-client

# These steps are derived from the mattermost-server/build/release.mk package target

echo Packaging RiffEdu mattermost

# Remove any old files
rm -Rf ${DIST_ROOT}

# Create needed directories
mkdir -p ${DIST_PATH}/bin
mkdir -p ${DIST_PATH}/data
mkdir -p ${DIST_PATH}/plugins
mkdir -p ${DIST_PATH}/logs
mkdir -p ${DIST_PATH}/prepackaged_plugins

# Resource directories
mkdir -p ${DIST_PATH}/config
cp -L config/{README.md,config-dev.json} ${DIST_PATH}/config
## We set the initial config below by modifying config-dev.json instead of the following:
## OUTPUT_CONFIG=${PWD}/${DIST_PATH}/config/config.json go generate ./config
cp -RL fonts ${DIST_PATH}
cp -RL templates ${DIST_PATH}
rm -rf ${DIST_PATH}/templates/*.mjml ${DIST_PATH}/templates/partials/
cp -RL i18n ${DIST_PATH}

# NOTE: these are development settings, we probably want to change them for
# production. IE for production set:
#   SiteURL = ???
#   AllowCorsFrom = ???
#   ListenAddress = :8000
#   EnableConsole = false
#   ConsoleLevel = INFO
#   ...other stuff? maybe use a different DB (postgres)?
#
# Email SMTP setting are defined for using AWS SES, but the user/pswd are confidential
# and must be added to the config after the service is running.
# The config is in a docker named volume so redeploying WILL NOT update these values
# unless you decide to delete that volume first, in which case it will be re-initialized
# with these values but will lose any values set after deployment or via the console.
MM_CONFIG_UPDATE=( '.ServiceSettings.SiteURL |= "https://NEW-DOMAIN.riffedu.com"'   \
               '|' '.ServiceSettings.ListenAddress |= ":8065"'                      \
               '|' '.ServiceSettings.AllowCorsFrom |= "*"'                          \
               '|' '.ServiceSettings.EnableDeveloper |= false'                      \
               '|' '.ServiceSettings.EnablePreviewFeatures |= false'                \
               '|' '.ServiceSettings.EnableTutorial |= false'                       \
               '|' '.ServiceSettings.EnableOnboardingFlow |= false'                 \
               '|' '.TeamSettings.SiteName |= "Riff Edu"'                           \
               '|' '.TeamSettings.EnableTeamCreation |= false'                      \
               '|' '.TeamSettings.MaxUsersPerTeam |= 500'                           \
               '|' '.TeamSettings.CustomDescriptionText |= "Your course collaboration platform. Connected teams have better outcomes."' \
               '|' '.TeamSettings.ExperimentalDefaultChannels |= ["course-support", "current-events"]' \
               '|' '.LogSettings.EnableConsole |= true'                             \
               '|' '.LogSettings.ConsoleLevel |= "ERROR"'                           \
               '|' '.FileSettings.Directory |= "'"${DIST_ROOT}/data/"'"'            \
               '|' '.FileSettings.EnablePublicLink |= true'                         \
               '|' '.FileSettings.PublicLinkSalt |= "'$(generate_salt)'"'           \
               '|' '.EmailSettings.SendEmailNotifications |= false'                 \
               '|' '.EmailSettings.FeedbackName |= "Riff Edu Support (SITE NAME)"'  \
               '|' '.EmailSettings.FeedbackEmail |= "support@riffanalytics.ai"'     \
               '|' '.EmailSettings.FeedbackOrganization |= "© Riff Analytics, Newton MA"' \
               '|' '.EmailSettings.ReplyToAddress |= "support@riffanalytics.ai"'    \
               '|' '.EmailSettings.SMTPServer |= "email-smtp.us-east-1.amazonaws.com"' \
               '|' '.EmailSettings.SMTPPort |= "465"'                               \
               '|' '.EmailSettings.SMTPUsername |= ""'                              \
               '|' '.EmailSettings.SMTPPassword |= ""'                              \
               '|' '.EmailSettings.EnableSMTPAuth |= true'                          \
               '|' '.EmailSettings.ConnectionSecurity |= "TLS"'                     \
               '|' '.EmailSettings.EnableEmailBatching |= true'                     \
               '|' '.EmailSettings.EmailBatchingBufferSize |= 256'                  \
               '|' '.EmailSettings.EmailBatchingInterval |= 30'                     \
               '|' '.EmailSettings.SkipServerCertificateVerification |= true'       \
               '|' '.EmailSettings.EmailNotificationContentsType |= "full"'         \
               '|' '.EmailSettings.InviteSalt |= "'$(generate_salt)'"'              \
               '|' '.EmailSettings.PasswordResetSalt |= "'$(generate_salt)'"'       \
               '|' '.EmailSettings.EnablePreviewModeBanner |= false'                \
               '|' '.ThemeSettings.DefaultTheme |= "riff"'                          \
               '|' '.SupportSettings.TermsOfServiceLink |= "https://www.riffanalytics.ai/terms-of-service"' \
               '|' '.SupportSettings.PrivacyPolicyLink |= "https://www.riffanalytics.ai/privacy-policy"' \
               '|' '.SupportSettings.SupportEmail |= "support@riffanalytics.ai"'    \
               '|' '.SupportSettings.EnableAskCommunityLink |= false'               \
               '|' '.NativeAppSettings.AppDownloadLink |= ""'                       \
               '|' '.NativeAppSettings.AndroidAppDownloadLink |= ""'                \
               '|' '.NativeAppSettings.IosAppDownloadLink |= ""'                    \
               '|' '.AnnouncementSettings.AdminNoticesEnabled |= false'             \
               '|' '.AnnouncementSettings.UserNoticesEnabled |= false'              \
               '|' '.AnnouncementSettings.NoticesURL |= ""'                         \
               '|' '.RateLimitSettings.Enable |= false'                             \
               '|' '.SqlSettings.DriverName |= "mysql"'                             \
               '|' '.SqlSettings.DataSource |= "'"mmuser:mostest@tcp(${DB_DOMAIN}:${DB_PORT})/mattermost_test?charset=utf8mb4,utf8\\u0026readTimeout=30s\\u0026writeTimeout=30s"'"' \
               '|' '.SqlSettings.AtRestEncryptKey |= "'$(generate_salt)'"'          \
               '|' '.PluginSettings.Enable |= true'                                 \
               '|' '.PluginSettings.EnableUploads |= true'                          \
               '|' '.PluginSettings.Directory |= "'"${DIST_ROOT}/plugins"'"'        \
               '|' '.PluginSettings.ClientDirectory |= "'"${DIST_ROOT}/client/plugins"'"' \
               '|' '.PluginSettings.EnableMarketplace |= false'                     \
               '|' '.PluginSettings.EnableRemoteMarketplace |= false'               \
               '|' '.PluginSettings.Plugins."ai.riffanalytics.lti".enable |= false' \
               '|' '.PluginSettings.Plugins."ai.riffanalytics.lti".enablesignaturevalidation |= true' \
               '|' '.PluginSettings.Plugins."ai.riffanalytics.lti".lmss |= ['       \
                        '{'                                                         \
                            '"Name": "Sample Client Name",'                         \
                            '"Type": "edx",'                                        \
                            '"OAuthConsumerKey": "sample_client_1234",'             \
                            '"OAuthConsumerSecret": "00112233445566778899aabbccddeeff",' \
                            '"Teams": {'                                            \
                                '"lms_lti-context_id-field_value": "team-slug"'     \
                            '},'                                                    \
                            '"PersonalChannels": {'                                 \
                                '"Type": "custom-properties",'                      \
                                '"ChannelList": {'                                  \
                                    '"capstone": {"IdProperty": "custom_team_id", "NameProperty": "custom_team_name"},' \
                                    '"plg": {"IdProperty": "custom_cohort_id", "NameProperty": "custom_cohort_name"}' \
                                '}'                                                 \
                            '}'                                                     \
                        '}'                                                         \
                    ']'                                                             \
                 )

# Use the dev config (until we figure out something better) as the initial config
# (convert the config update array to a string so it can be a single argument to jq)
JQ_FILTER=${MM_CONFIG_UPDATE[@]}
echo Creating initial config.json file...
jq "${JQ_FILTER}" ${DIST_PATH}/config/config-dev.json > ${DIST_PATH}/config/config.json.save
cp ${DIST_PATH}/config/config.json.save ${DIST_PATH}/config/config.json

# Package webapp
echo Copying over the client files...
mkdir -p ${DIST_PATH}/client/plugins
cp -RL ${BUILD_WEBAPP_DIR}/dist/* ${DIST_PATH}/client

# Download MMCTL
echo Downloading mmctl...
scripts/download_mmctl_release.sh "Linux" ${DIST_PATH}/bin

# Help files
echo Copying over the help files...
cp build/MIT-COMPILED-LICENSE.md ${DIST_PATH}
cp NOTICE.txt ${DIST_PATH}
cp README.md ${DIST_PATH}
if [ -f ../manifest.txt ]; then
    cp ../manifest.txt ${DIST_PATH}
fi

# Copy linux binary
echo Copying over the server executable file...
cp ${GOBIN}/mattermost ${DIST_PATH}/bin # from native bin dir, not cross-compiled
