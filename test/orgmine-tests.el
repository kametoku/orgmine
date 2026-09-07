;;; orgmine-tests.el --- Tests for orgmine.el  -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'orgmine)

(defconst orgmine-test-sample-data
  "
#+SEQ_TODO: New(n) Open(o) Resolved(r) Feedback(f) | Closed(c)
#+TAGS: { UPDATE_ME(u) CREATE_ME(c) REFILE_ME(r) }
#+TAGS: { project(p) tracker(t) version(v) issue(i) description(d) journals(J) journal(j) }
* SandBox ([[redmine:projects/sandbox]])                                      :project:
  :PROPERTIES:
  :om_project: 1:SandBox
  :om_created_on: 2015-07-31T06:40:56Z
  :om_updated_on: 2015-08-18T05:42:26Z
  :om_status: 1
  :om_identifier: sandbox
  :END:
** Description                                                                :description:
   #+begin_src gfm
     This is a sandbox project. Feel free to play with this project.
   #+end_src

* Tasks                                                                       :tracker:
  :PROPERTIES:
  :om_tracker: 4:Task
  :om_fixed_version: !*
  :END:
  - tickets which do not belong to any version.
** New [[redmine:issues/24][#24]] Implement orgmine-xxx function              :issue:
   SCHEDULED: <2015-09-11 Fri>
   :PROPERTIES:
   :om_id:    24
   :om_tracker: 4:Task
   :om_created_on: 2015-09-11T14:01:25Z
   :om_updated_on: 2015-09-19T18:30:18Z
   :om_status: 1:New
   :om_fixed_version: 3:Test
   :om_start_date: [2015-09-11 Fri]
   :om_done_ratio: 0
   :om_project: 1:SandBox
   :END:
*** Description                                                               :description:
    #+begin_src gfm
      This is a hard part.
    #+end_src
*** Attachments                                                               :attachments:
    - [[http://redmine.example.org/attachments/download/12/a.jpg][a.jpg]] (25370 bytes) Tokuya Kameshima [2015-09-14 Mon 01:13]
      abcdefg
*** Journals                                                                  :journals:
**** [[redmine:issues/24#note-2]] [2015-09-20 Sun 03:30] Tokuya Kameshima     :journal:
     :PROPERTIES:
     :om_count: 2
     :END:
     #+begin_src gfm
       This is a note...
     #+end_src
**** [[redmine:issues/24#note-1]] [2015-09-14 Mon 01:15] Tokuya Kameshima     :journal:
     :PROPERTIES:
     :om_count: 1
     :END:
     :DETAILS:
     - attachment_11: ADDED -> \"naorio.JPG\"
     :END:
"
  "Sample Org mode buffer content for orgmine tests.")

(defmacro orgmine-with-test-buffer (&rest body)
  "Evaluate BODY in a temporary org-mode buffer with sample data."
  (declare (indent 0) (debug t))
  `(with-temp-buffer
     (insert orgmine-test-sample-data)
     (org-mode)
     (org-set-regexps-and-options)
     (let ((orgmine-servers  '(("redmine"
                                (host . "http://redmine.example.com")
                                (api-key . "blabblabblab")))))
       (orgmine-mode t)
       (setq orgmine-statuses '((:id 1 :name "New")
                                (:id 2 :name "Open")))
     (goto-char (point-min))
     ,@body)))

(ert-deftest orgmine-test-idname-to-id ()
  "Test extracting ID from ID:NAME format."
  (should (equal (orgmine-idname-to-id "1:SandBox") "1"))
  (should (equal (orgmine-idname-to-id "24") "24"))
  (should (equal (orgmine-idname-to-id "84:MyProject") "84")))

(ert-deftest orgmine-test-redmine-date-conversion ()
  "Test parsing org-mode timestamp to redmine date."
  (should (equal (orgmine-redmine-date "[2015-09-04 Fri]") "2015-09-04")))

(ert-deftest orgmine-test-get-project-properties ()
  "Test retrieving properties from a Project headline."
  (orgmine-with-test-buffer
    (re-search-forward "\\* SandBox")
    (let ((pom (point)))
      (should (equal (orgmine-get-property pom 'project) '(:project_id "1")))
      (should (equal (orgmine-get-property pom 'status) '(:status "1")))
      (should (equal (orgmine-get-property pom 'identifier) '(:identifier "sandbox"))))))

(ert-deftest orgmine-test-get-tracker-properties ()
  "Test retrieving properties from a Tracker headline."
  (orgmine-with-test-buffer
    (re-search-forward "\\* Tasks")
    (let ((pom (point)))
      (should (equal (orgmine-get-property pom 'tracker) '(:tracker_id "4")))
      (should (equal (nth 1 (orgmine-get-property pom 'fixed_version nil nil t)) "!*")))))

(ert-deftest orgmine-test-get-issue-properties ()
  "Test retrieving properties from an Issue headline."
  (orgmine-with-test-buffer
    (search-forward "Implement orgmine-xxx")
    (let ((pom (point)))
      (should (equal (orgmine-get-property pom 'id) '(:id "24")))
      (should (equal (orgmine-get-property pom 'tracker) '(:tracker_id "4"))))))

(ert-deftest orgmine-test-extract-note-from-description ()
  "Test extracting gfm block from description headline."
  (orgmine-with-test-buffer
    (re-search-forward "\\*\\*\\* Description")
    (let* ((headline (org-element-at-point))
           (note (orgmine-note headline)))
      (should (stringp note))
      (should (string-match-p "This is a hard part." note)))))

(ert-deftest orgmine-test-update-title ()
  "Test updating the headline title."
  (orgmine-with-test-buffer
    (search-forward "Implement orgmine-xxx")
    (org-back-to-heading t)
    (orgmine-update-title "[[redmine:issues/24][#24]] Updated Subject")
    (should (string-match-p "Updated Subject" (thing-at-point 'line)))))

(ert-deftest orgmine-test-set-properties ()
  "Test setting properties from Redmine plist."
  (orgmine-with-test-buffer
    (search-forward "Implement orgmine-xxx")
    (org-back-to-heading t)
    (let ((dummy-redmine-issue
           '(:done_ratio 50
             :assigned_to (:id 1 :name "Tokuya Kameshima"))))
      (orgmine-set-properties 'issue dummy-redmine-issue '(done_ratio assigned_to))
      (should (equal (org-entry-get (point) "om_done_ratio") "50"))
      (should (equal (org-entry-get (point) "om_assigned_to") "1:Tokuya Kameshima")))))

(ert-deftest orgmine-test-collect-update-plist ()
  "Test collecting all update data into a plist from an Issue entry."
  (orgmine-with-test-buffer
    (search-forward "Implement orgmine-xxx")
    (org-back-to-heading t)
    (save-excursion
      (search-forward "*** Description")
      (org-back-to-heading t)
      (org-toggle-tag "UPDATE_ME" 'on)
      (goto-char (point-min))
      (search-forward "note-2")
      (org-back-to-heading t)
      (org-toggle-tag "UPDATE_ME" 'on))
    (let* ((issue-element (org-element-at-point))
           (plist (orgmine-collect-update-plist issue-element :subject)))
      (should (equal (plist-get plist :id) "24"))
      (should (equal (plist-get plist :subject) "Implement orgmine-xxx function"))
      (should (equal (plist-get plist :tracker_id) "4"))
      (let ((desc (plist-get plist :description)))
        (should (stringp desc))
        (should (string-match-p "This is a hard part." desc)))
      (let ((notes (plist-get plist :notes)))
        (should (stringp notes))
        (should (string-match-p "This is a note..." notes))))))

(ert-deftest orgmine-test-insert-description ()
  "Test updating the description text block inside an issue."
  (orgmine-with-test-buffer
    (search-forward "Implement orgmine-xxx")
    (org-back-to-heading t)
    (let* ((region (orgmine-subtree-region))
           (beg (car region))
           (end (cdr region))
           (new-desc "This is a NEWLY UPDATED description text."))
      (orgmine-insert-description new-desc beg end t)
      (goto-char beg)
      (should (search-forward new-desc end t))
      (goto-char beg)
      (should-not (search-forward "This is a hard part." end t)))))


(ert-deftest orgmine-test-time-entry-key-equality ()
  "Time-entry and parsed-clock representations share a deduplication key."
  (let ((entry '(:spent_on "2024-01-02" :hours 1.5 :comments "  reviewed  "))
        (clock (list (org-time-string-to-time "[2024-01-02 Tue 09:00]")
                     (org-time-string-to-time "[2024-01-02 Tue 10:30]")
                     90 "reviewed")))
    (should (equal (orgmine-time-entry-key entry)
                   (orgmine-clock-line-key clock)))
    (should (equal (orgmine-time-entries-missing-locally (list entry)
                                                         (list clock))
                   nil))
    (should (equal (orgmine-clocks-missing-remotely (list clock)
                                                    (list entry))
                   nil))))

(ert-deftest orgmine-test-parse-logbook-clocks ()
  "Parse closed clocks and their immediately following note only."
  (with-temp-buffer
    (insert "* Issue :issue:\n"
            "  :PROPERTIES:\n  :om_id: 24\n  :END:\n"
            "  :LOGBOOK:\n"
            "  CLOCK: [2024-01-02 Tue 09:00]--[2024-01-02 Tue 10:00] =>  1:00\n"
            "  - first note\n"
            "  CLOCK: [2024-01-02 Tue 10:00]--[2024-01-02 Tue 10:30] =>  0:30\n"
            "  :END:\n"
            "** Child\n  :LOGBOOK:\n"
            "  CLOCK: [2024-01-02 Tue 12:00]--[2024-01-02 Tue 13:00] =>  1:00\n"
            "  :END:\n")
    (org-mode)
    (org-set-regexps-and-options)
    (orgmine-mode t)
    (goto-char (point-min))
    (let ((clocks (orgmine-parse-logbook-clocks (org-element-at-point))))
      (should (= (length clocks) 2))
      (should (= (nth 2 (car clocks)) 60))
      (should (equal (nth 3 (car clocks)) "first note"))
      (should (= (nth 2 (cadr clocks)) 30))
      (should-not (nth 3 (cadr clocks))))))

(ert-deftest orgmine-test-pull-time-entries-stacks-clocks ()
  "Pull only missing entries and stack same-day synthesized clocks."
  (with-temp-buffer
    (insert "* Issue :issue:\n"
            "  :PROPERTIES:\n  :om_id: 24\n  :END:\n"
            "  :LOGBOOK:\n  :END:\n"
            "** Child\n")
    (org-mode)
    (org-set-regexps-and-options)
    (orgmine-mode t)
    (goto-char (point-min))
    (let ((remote '((:id 1 :issue_id 24 :spent_on "2024-01-02"
                         :hours 1.0 :comments "first")
                     (:id 2 :issue_id 24 :spent_on "2024-01-02"
                         :hours 0.5 :comments "second"))))
      (cl-letf (((symbol-function 'elmine/get-issue-time-entries)
                 (lambda (&rest _args) remote)))
        (should (= (orgmine-pull-time-entries) 2)))
      (should (= (count-matches "CLOCK:") 2))
      (should (string-match-p
               "CLOCK: \\[2024-01-02 Tue 09:00\\]--\\[2024-01-02 Tue 10:00\\] =>  1:00"
               (buffer-string)))
      (should (string-match-p
               "CLOCK: \\[2024-01-02 Tue 10:00\\]--\\[2024-01-02 Tue 10:30\\] =>  0:30"
               (buffer-string)))
      (should (string-match-p "  - first" (buffer-string)))
      (should (string-match-p "  - second" (buffer-string)))
      (should (string-match-p "\\*\\* Child" (buffer-string))))))

(ert-deftest orgmine-test-push-time-entries-creates-missing-clocks ()
  "Push only missing closed clocks and ignore a running clock."
  (with-temp-buffer
    (insert "* Issue :issue:\n"
            "  :PROPERTIES:\n  :om_id: 24\n  :om_activity: Development\n  :END:\n"
            "  :LOGBOOK:\n"
            "  CLOCK: [2024-01-03 Wed 09:00]--[2024-01-03 Wed 10:00] =>  1:00\n"
            "  - first\n"
            "  CLOCK: [2024-01-03 Wed 10:00]--[2024-01-03 Wed 10:30] =>  0:30\n"
            "  - second\n"
            "  CLOCK: [2024-01-03 Wed 11:00]\n"
            "  :END:\n")
    (org-mode)
    (org-set-regexps-and-options)
    (orgmine-mode t)
    (goto-char (point-min))
    (let ((remote '((:id 1 :issue_id 24 :spent_on "2024-01-03"
                         :hours 1.0 :comments "first")))
          (created nil)
          (calls 0))
      (cl-letf (((symbol-function 'elmine/get-time-entry-activities)
                 (lambda (&rest _args)
                   '((:id 7 :name "Development"))))
                ((symbol-function 'elmine/get-issue-time-entries)
                 (lambda (&rest _args)
                   (setq calls (1+ calls))
                   (if (= calls 1)
                       remote
                     (append remote (list (car created))))))
                ((symbol-function 'elmine/create-time-entry)
                 (lambda (params)
                   (setq created (cons params created)))))
        (should (= (orgmine-push-time-entries) 1)))
      (should (equal created
                     '((:issue_id "24" :spent_on "2024-01-03"
                        :hours 0.5 :activity_id 7 :comments "second")))))))

(ert-deftest orgmine-test-time-entry-sync-is-idempotent ()
  "A second sync after Redmine accepts pushed entries is a no-op."
  (with-temp-buffer
    (insert "* Issue :issue:\n"
            "  :PROPERTIES:\n  :om_id: 24\n  :END:\n"
            "  :LOGBOOK:\n"
            "  CLOCK: [2024-01-04 Thu 09:00]--[2024-01-04 Thu 10:00] =>  1:00\n"
            "  - shipped\n"
            "  :END:\n")
    (org-mode)
    (org-set-regexps-and-options)
    (orgmine-mode t)
    (goto-char (point-min))
    (let ((remote nil)
          (created nil)
          (orgmine-time-entry-activity 7))
      (cl-letf (((symbol-function 'elmine/get-issue-time-entries)
                 (lambda (&rest _args) remote))
                ((symbol-function 'elmine/create-time-entry)
                 (lambda (params)
                   (setq created (cons params created))
                   (setq remote
                         (append remote
                                 (list (list :id 1 :issue_id 24
                                             :spent_on "2024-01-04"
                                             :hours 1.0
                                             :comments "shipped"
                                             :activity '(:id 7 :name "Dev"))))))))
        (orgmine-sync-time-entries)
        (let ((after-first (buffer-string)))
          (setq created nil)
          (orgmine-sync-time-entries)
          (should (equal (buffer-string) after-first))
          (should-not created))))))

(provide 'orgmine-tests)
;;; orgmine-tests.el ends here
