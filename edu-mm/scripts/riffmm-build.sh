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
cp -RL config ${DIST_PATH}
cp -RL fonts ${DIST_PATH}
cp -RL templates ${DIST_PATH}
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
MM_CONFIG_UPDATE=( '.ServiceSettings.SiteURL |= "https://nexted.riffedu.com"'       \
               '|' '.ServiceSettings.ListenAddress |= ":8065"'                      \
               '|' '.ServiceSettings.AllowCorsFrom |= "*"'                          \
               '|' '.ServiceSettings.EnablePreviewFeatures |= false'                \
               '|' '.ServiceSettings.EnableDeveloper |= false'                      \
               '|' '.ServiceSettings.EnableTutorial |= false'                       \
               '|' '.TeamSettings.SiteName |= "Riff Edu"'                           \
               '|' '.TeamSettings.MaxUsersPerTeam |= 200'                           \
               '|' '.TeamSettings.CustomDescriptionText |= "Your course collaboration platform. Connected teams have better outcomes."' \
               '|' '.TeamSettings.ExperimentalDefaultChannels |= ["course-support", "coding-help", "business-help", "off-topic"]' \
               '|' '.LogSettings.EnableConsole |= true'                             \
               '|' '.LogSettings.ConsoleLevel |= "DEBUG"'                           \
               '|' '.FileSettings.Directory |= "'"${DIST_ROOT}/data/"'"'            \
               '|' '.FileSettings.EnablePublicLink |= true'                         \
               '|' '.FileSettings.PublicLinkSalt |= "'$(generate_salt)'"'           \
               '|' '.EmailSettings.SendEmailNotifications |= false'                 \
               '|' '.EmailSettings.FeedbackName |= "Riff Edu Support"'              \
               '|' '.EmailSettings.FeedbackEmail |= "support@rifflearning.com"'     \
               '|' '.EmailSettings.FeedbackOrganization |= "© Riff Learning, Inc., Newton MA"' \
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
               '|' '.SupportSettings.TermsOfServiceLink |= "https://www.rifflearning.com/terms-of-service"' \
               '|' '.SupportSettings.PrivacyPolicyLink |= "https://www.rifflearning.com/privacy-policy"' \
               '|' '.SupportSettings.SupportEmail |= "support@rifflearning.com"'    \
               '|' '.RateLimitSettings.Enable |= true'                              \
               '|' '.SqlSettings.DriverName |= "mysql"'                             \
               '|' '.SqlSettings.DataSource |= "'"mmuser:mostest@tcp(${DB_DOMAIN}:${DB_PORT})/mattermost_test?charset=utf8mb4,utf8\\u0026readTimeout=30s\\u0026writeTimeout=30s"'"' \
               '|' '.SqlSettings.AtRestEncryptKey |= "'$(generate_salt)'"'          \
               '|' '.PluginSettings.Directory |= "'"${DIST_ROOT}/plugins"'"'        \
               '|' '.PluginSettings.ClientDirectory |= "'"${DIST_ROOT}/client/plugins"'"' \
               '|' '.LTISettings.Enable |= true'                                    \
               '|' '.LTISettings.EnableSignatureValidation |= true'                 \
               '|' '.LTISettings.LMSs |= []'                                        \
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

# Copy linux binary
echo Copying over the server executable file...
cp ${GOPATH}/bin/mattermost ${DIST_PATH}/bin # from native bin dir, not cross-compiled
