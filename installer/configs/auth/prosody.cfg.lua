plugin_paths = { "/usr/share/jitsi-meet/prosody-plugins/" }

-- domain mapper options, must at least have domain base set to use the mapper
muc_mapper_domain_base = "JITSI_DOMAIN_NAME";

turncredentials_secret = "TURN_SECRET";

turncredentials = {
  { type = "stun", host = "JITSI_DOMAIN_NAME", port = "443" },
  { type = "turn", host = "JITSI_DOMAIN_NAME", port = "443", transport = "udp" },
  { type = "turns", host = "JITSI_DOMAIN_NAME", port = "443", transport = "tcp" }
};

cross_domain_bosh = false;
consider_bosh_secure = true;

VirtualHost "JITSI_DOMAIN_NAME"
        -- enabled = false -- Remove this line to enable this host
        authentication = "internal_plain"
        -- Properties below are modified by jitsi-meet-tokens package config
        -- and authentication above is switched to "token"
        --app_id="example_app_id"
        --app_secret="example_app_secret"
        -- Assign this host a certificate for TLS, otherwise it would use the one
        -- set in the global section (if any).
        -- Note that old-style SSL on port 5223 only supports one certificate, and will always
        -- use the global one.
        ssl = {
                key = "/etc/prosody/certs/JITSI_DOMAIN_NAME.key";
                certificate = "/etc/prosody/certs/JITSI_DOMAIN_NAME.crt";
        }
        speakerstats_component = "speakerstats.JITSI_DOMAIN_NAME"
        conference_duration_component = "conferenceduration.JITSI_DOMAIN_NAME"
        -- we need bosh
        modules_enabled = {
            "bosh";
            "pubsub";
            "ping"; -- Enable mod_ping
            "speakerstats";
            "turncredentials";
            "conference_duration";
        }
        c2s_require_encryption = false

Component "conference.JITSI_DOMAIN_NAME" "muc"
    storage = "none"
    modules_enabled = {
        "muc_meeting_id";
        "muc_domain_mapper";
        -- "token_verification";
    }
    admins = { "focus@auth.JITSI_DOMAIN_NAME" }

-- internal muc component
Component "internal.auth.JITSI_DOMAIN_NAME" "muc"
    storage = "none"
    modules_enabled = {
      "ping";
    }
    admins = { "focus@auth.JITSI_DOMAIN_NAME", "jvb@auth.JITSI_DOMAIN_NAME" }

VirtualHost "auth.JITSI_DOMAIN_NAME"
    ssl = {
        key = "/etc/prosody/certs/auth.JITSI_DOMAIN_NAME.key";
        certificate = "/etc/prosody/certs/auth.JITSI_DOMAIN_NAME.crt";
    }
    authentication = "internal_plain"

Component "focus.JITSI_DOMAIN_NAME"
    component_secret = "JICOFO_SECRET"

Component "speakerstats.JITSI_DOMAIN_NAME" "speakerstats_component"
    muc_component = "conference.JITSI_DOMAIN_NAME"

Component "conferenceduration.JITSI_DOMAIN_NAME" "conference_duration_component"
    muc_component = "conference.JITSI_DOMAIN_NAME"

VirtualHost "guest.JITSI_DOMAIN_NAME"
    authentication = "anonymous"
    c2s_require_encryption = false
