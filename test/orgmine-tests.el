;;; orgmine-tests.el --- Tests for orgmine.el  -*- lexical-binding: t; -*-
(require 'ert)
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

(provide 'orgmine-tests)
;;; orgmine-tests.el ends here
