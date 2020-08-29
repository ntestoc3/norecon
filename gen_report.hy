#!/usr/bin/env hy

(require [hy.extra.anaphoric [*]]
         [helpers [*]]
         )

(import os
        logging
        sys
        re
        json
        argparse

        [datetime [datetime]]
        [helpers [*]]
        [project [*]]
        [shutil [copy]]
        [jinja2 [Environment
                 FileSystemLoader
                 PackageLoader]]
        [glob [glob]]
        [iploc [get-location]]
        )

(setv curr-dir (try --file--
                    (os.path.dirname --file--)
                    (except [NameError]
                      (os.getcwd))))

(setv env (Environment :loader (FileSystemLoader (os.path.join curr-dir "templates"))
                       :trim-blocks True
                       :lstrip-blocks True))

(defn render->file
  [template-name data filepath]
  (with [w (open filepath "w")]
    (-> (env.get-template template-name)
        (.render data)
        (w.write))))


(defn render-whois
  [project-dir]
  (setv save-path (os.path.join project-dir "notes" "whois"))
  (os.makedirs save-path :exist-ok True)
  (for [f (glob (os.path.join project-dir "whois" "*.json"))]
    (setv target (-> (os.path.basename f)
                     (os.path.splitext)
                     first))
    (render->file "whois.md" {"data" (read-whois target project-dir)
                              "target" target}
                  (os.path.join save-path f"{target}.md"))))

(defn render-domain
  [project-dir]
  (setv save-path (os.path.join project-dir "notes" "domain"))
  (os.makedirs save-path :exist-ok True)
  (for [f (glob (os.path.join project-dir "domain" "*.json"))]
    (setv target (-> (os.path.basename f)
                     (os.path.splitext)
                     first))
    (render->file "domain.md" {"data" (read-domain target project-dir)
                              "target" target}
                  (os.path.join save-path f"{target}.md"))))

(defn gen-screen-info
  [target project-dir]
  (some-> (read-screen-session target project-dir)
          (.get "pages")
          (.items)
          (as-> $
                (lfor [k d] $
                      :do (do
                            (setv (of d "target") k)
                            (as-> (.get d "screenshotPath") spath
                                  (when spath
                                    (-> (copy (os.path.join project-dir "screen" spath)
                                              (os.path.join project-dir "notes" "resources"))
                                        (os.path.relpath (os.path.join project-dir "notes" "ip"))
                                        (->> (setv (of d "screenshotPath")))))))
                      d))))

(defn render-ip
  [project-dir]
  (setv save-path (os.path.join project-dir "notes" "ip"))
  (os.makedirs save-path :exist-ok True)
  (for [f (glob (os.path.join project-dir "ip" "*.json"))]
    (setv target (-> (os.path.basename f)
                     (os.path.splitext)
                     first))
    (render->file "ip.md" {"data" (read-ip target project-dir)
                           "screen" (gen-screen-info target project-dir)
                           "location" (get-location target)
                           "target" target}
                  (os.path.join save-path f"{target}.md"))))

(defn render-record
  [project-dir]
  (setv save-path (os.path.join project-dir "notes" "record"))
  (os.makedirs save-path :exist-ok True)
  (for [f (glob (os.path.join project-dir "record" "*.json"))]
    (setv target (-> (os.path.basename f)
                     (os.path.splitext)
                     first))
    (render->file "record.md" {"data" (read-record target project-dir)
                               "screen" (gen-screen-info target project-dir)
                               "target" target}
                  (os.path.join save-path f"{target}.md"))))
