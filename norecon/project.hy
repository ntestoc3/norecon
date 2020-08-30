
(import json
        logging
        os)

(defn read-project-file
  [project-dir &rest paths]
  (setv fpath (os.path.join project-dir #* paths))
  (when (os.path.exists fpath)
    (try (with [f (open fpath)]
           (json.load f))
         (except [e Exception]
           (logging.warn "load project json file %s error: %s." fpath e)))))

(defn read-ip
  [ip project-dir]
  (read-project-file project-dir "ip" f"{ip}.json"))

(defn read-whois
  [host project-dir]
  (read-project-file project-dir "whois" f"{host}.json"))

(defn read-domain
  [domain project-dir]
  (read-project-file project-dir "domain" f"{domain}.json"))

(defn read-record
  [domain project-dir]
  (read-project-file project-dir "record" f"{domain}.json"))

(defn read-screen-session
  [domain project-dir]
  (read-project-file project-dir "screen" f"{domain}.json"))

