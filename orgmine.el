;;; orgmine.el --- minor mode for org-mode with redmine integration

;; Copyright (C) 2015-2016 Tokuya Kameshima

;; Author: Tokuya Kameshima <kametoku at gmail dot com>
;; Keywords: outlines, hypermedia, calendar, wp
;; Homepage: http://github.com/kametoku/orgmine

;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; orgmine is a minor mode for org-mode with Redmine integration.
;; In a orgmine-mode buffer, you can retrieve the issues from Redmine,
;; edit the entries locally, and submit the changes to Redmine.

;; - [ ] implement orgmine-copy-issue to push an issue tree to clipboard
;;   so that it will be inserted into the buffer as a new issue.
;; - [ ] suppress adding TODO keyword to headlines without :issue: tag. If
;;   a headline already has a TODO keyword, changing todo status is
;;   permitted.  Alternatively, if the current position is under an
;;   issue subtree, changing todo keyword will be applied to the issue
;;   headline.  This is the case for setting properties as well.
;; - [ ] improve syncing process with cache effectively.
;; - [ ] changing issue status will updates TODO keyword as well.
;; - [ ] more supports for custom fields.
;; - [ ] orgmine-y-or-n permits scroll the plist buffer.
;; - [ ] a command to show properties of the current entry in other window.

;;; Code:

(require 'elmine)
(require 's)
(require 'org)
(require 'org-archive)
(require 'timezone)

(defgroup orgmine nil
  "Options concerning orgmie minor mode."
  :tag "Org Mine"
  :group 'org)

(defcustom orgmine-issue-title-format
  "[[redmine:issues/%{id}][#%{id}]] %{subject}"
  "Title format for issue entry."
  :group 'orgmine)

(defcustom orgmine-journal-title-format
  "[[redmine:issues/%{id}#note-%{count}][V#%{id}-%{count}]] %{created_on} %{author}"
  "Title format for journal entry."
  :group 'orgmine)

(defcustom orgmine-version-title-format
  "[[redmine:versions/%{id}][V#%{id}]] %{name}"
  "Title format for version entry."
  :group 'orgmine)

(defcustom orgmine-tracker-title-format "%{name}"
  "Title format for tracker entry."
  :group 'orgmine)

(defcustom orgmine-project-title-format
  "[[redmine:projects/%{identifier}][%{identifier}]] %{name}"
  "Title format for project entry."
  :group 'orgmine)

(defcustom orgmine-wiki-page-title-format
  "[[redmine:projects/%{project}/wiki/%{title}][%{title}]]"
  "Title format for wiki page entry."
  :group 'orgmine)

(defcustom orgmine-title-format-regexp
  (let ((brackert-link-regexp
	 "\\[\\[\\(?:[^][]+\\)\\]\\(?:\\[\\(?:[^][]+\\)\\]\\)?\\]"))
    (concat "^[ \t]*" brackert-link-regexp "[ \t]*\\(.*?\\)"
	    "[ \t]*\\(?:(" brackert-link-regexp ")\\)?$"))
  "Regular express to extract subject part from headline title."
  :group 'orgmine)

(defcustom orgmine-user-name-format "%{firstname} %{lastname}"
  "User name format."
  :group 'orgmine)

(defcustom orgmine-attachment-format
  (concat "[[%{content_url}][%{filename}]] (%{filesize} bytes)"
	  " %{author.name} %{created_on}")
  "attachment item format."
  :group 'orgmine)

(defcustom orgmine-journal-details-drawer "DETAILS"
  "Drawer name to hold journal details."
  :group 'orgmine)

(defcustom orgmine-note-block-begin "#+begin_src gfm"
  ""
  :group 'orgmine)

(defcustom orgmine-note-block-end "#+end_src"
  ""
  :group 'orgmine)

(defcustom orgmine-tags
  '((update-me . "UPDATE_ME")
    (create-me . "CREATE_ME")
    (project . "project")
    (tracker . "tracker")
    (versions . "versions")
    (version . "version")
    (issue . "issue")
    (description . "description")
    (journals . "journals")
    (journal . "journal")
    (attachments . "attachments")
    (wiki . "wiki"))
  "Alist of tags which are used in orgmine mode."
  :group 'orgmine)

(defvar orgmine-tag-update-me)
(defvar orgmine-tag-create-me)
(defvar orgmine-tag-project)
(defvar orgmine-tag-tracker)
(defvar orgmine-tag-versions)
(defvar orgmine-tag-version)
(defvar orgmine-tag-issue)
(defvar orgmine-tag-description)
(defvar orgmine-tag-journals)
(defvar orgmine-tag-journal)
(defvar orgmine-tag-attachments)
(defvar orgmine-tag-wiki)

(defcustom orgmine-servers
  '(("redmine"
     (host . "http://www.example.com")
     (api-key . "blabblabblab")
     (issue-title-format . "[[redmine:issues/%{id}][#%{id}]] %{subject}")
     (journal-title-format
      . "[[redmine:issues/%{id}#note-%{count}][V#%{id}-%{count}]] %{created_on} %{author}")
     (version-title-format . "[[redmine:versions/%{id}][V#%{id}]] %{name}")
     (tracker-title-format . "%{name}")
     (project-title-format
      . "[[redmine:projects/%{identifier}][%{identifier}]] %{name}")
     (user-name-format . "%{firstname} %{lastname}")
     (default-todo-keyword . "New"))
    ("localhost"
     (hoge)
     (host . "http://localhost:8080/redmine")
     (api-key . "XXX")
     (issue-title-format . "[\[localhost:issues/%{id}][#%{id}]] %{subject}")
     (journal-title-format
      . "[\[localhost:issues/%{id}#note-%{count}][V#%{id}-%{count}]] %{created_on} %{author}")
     (version-title-format . "[\[localhost:versions/%{id}][V#%{id}]] %{name}")
     (project-title-format . "[\[localhost:projects/%{identifier}][%{name}]]")
     (user-name-format . "%{firstname} %{lastname}")
     (default-todo-keyword . "New")))
  "An alist of redmine servers.
Each element has the form (NAME CONFIGURATION)."
  :group 'orgmine)

(defcustom orgmine-setup-hook nil
  "Hook called in `orgmine-setup'."
  :group 'orgmine
  :type 'hook)

(defcustom orgmine-issue-buffer-hook nil
  "Hook called in `orgmine-issue-buffer'."
  :group 'orgmine
  :type 'hook)

;; ;; workaround for decode the returned string as utf-8
;; (defadvice json-read-string (around json-read-string-decode activate)
;;   "Decode string processed in `json-read-string' as utf-8."
;;   (let ((string ad-do-it))
;;     (decode-coding-string string 'utf-8)))

;; redefine the function for workaround
(defun orgmine/json-read-string ()
  "Read the JSON string at point."
  (unless (char-equal (json-peek) ?\")
    (signal 'json-string-format (list "doesn't start with '\"'!")))
  ;; Skip over the '"'
  (json-advance)
  (let ((characters '())
        (char (json-peek)))
    (while (not (char-equal char ?\"))
      (push (if (char-equal char ?\\)
                (json-read-escaped-char)
              (json-pop))
            characters)
      (setq char (json-peek)))
    ;; Skip over the '"'
    (json-advance)
    (if characters
;; kame<<<
;; 	(apply 'string (nreverse characters))
;; =======
        (decode-coding-string (apply 'string (nreverse characters))
			      'utf-8)
;; >>>kame
      "")))

(defalias 'json-read-string 'orgmine/json-read-string)

;; redefine the function for workaround
(defun orgmine/api-raw (method path data params)
  "Perform a raw HTTP request with given METHOD, a relative PATH and a
plist of PARAMS for the query."
  (let* ((redmine-host (if (boundp 'redmine-host)
                           redmine-host
                         elmine/host))
         (redmine-api-key (if (boundp 'redmine-api-key)
                              redmine-api-key
                            elmine/api-key))
         (url (elmine/api-build-url path params))
         (url-request-method method)
         (url-request-extra-headers
          `(("Content-Type" . "application/json")
            ("X-Redmine-API-Key" . ,redmine-api-key)))
         (url-request-data data)
         header-end status header body)
    (save-excursion
      (switch-to-buffer (url-retrieve-synchronously url))
      (beginning-of-buffer)
      (setq header-end (save-excursion
                         (if (re-search-forward "^$" nil t)
                             (progn
                               (forward-char)
                               (point))
                           (point-max))))
      (when (re-search-forward "^HTTP/\\(1\\.0\\|1\\.1\\) \\([0-9]+\\) \\([A-Za-z ]+\\)$" nil t)
        (setq status (plist-put status :code (string-to-number (match-string 2))))
        (setq status (plist-put status :text (match-string 3))))
      (while (re-search-forward "^\\([^:]+\\): \\(.*\\)" header-end t)
        (setq header (cons (match-string 1) (cons (match-string 2) header))))
      (unless (eq header-end (point-max))
;; kame<<<
;;         (setq body (url-unhex-string
;;                     (buffer-substring header-end (point-max)))))
;; =======
	;; the body part is encoded in utf-8.
        (setq body (buffer-substring header-end (point-max))))
;; >>>kame
      (kill-buffer))
    `(:status ,status
      :header ,header
      :body ,body)))

(defalias 'elmine/api-raw 'orgmine/api-raw)

;;; XXX
;; http://www.redmine.org/projects/redmine/wiki/Rest_IssueJournals
;; '(:journals ((:details ((:new_value "3" :name "fixed_version_id" :property "attr"))
;;               :created_on "2015-08-02T14:19:02Z"
;;               :notes "" :user (:name "Tokuya Kameshima" :id 3) :id 3)
;;              ...))
(defun orgmine/get-issue-with-journals (id)
  "Get a specific issue including journals, relations and attachments via id."
;;   (elmine/api-get :issue (format "/issues/%s.json?include=journals" id)))
;;   (elmine/api-get :issue (format "/issues/%s.json" id) :include "journals"))
  (elmine/api-get :issue (format "/issues/%s.json" id)
		  :include "journals,relations,attachments"))

(defalias 'elmine/get-issue-with-journals 'orgmine/get-issue-with-journals)

(defun orgmine/get-project-trackers (project)
  "Get trackers of a specific project."
;;   (elmine/api-get :issue (format "/issues/%s.json?include=journals" id)))
  (let ((plist (elmine/api-get :project (format "/projects/%s.json" project)
			       :include "trackers")))
    (plist-get plist :trackers)))

(defalias 'elmine/get-project-trackers 'orgmine/get-project-trackers)

(defun orgmine/get-users ()
  "Get a list with users."
  (elmine/api-get-all :users "/users.json"))

(defalias 'elmine/get-users 'orgmine/get-users)

(defun orgmine/get-custom-fields (filters)
  "Get a list with custom fields."
  (apply #'elmine/api-get-all :custom_fields "/custom_fields.json" filters))

(defalias 'elmine/get-custom-fields 'orgmine/get-custom-fields)

(defun orgmine/create-relation (&rest params)
  "Create a new relation"
  (let* ((object (if (listp (car params)) (car params) params))
         (issue-id (plist-get object :issue_id))
	 (issue-to-id (plist-get object :issue_to_id))
	 (relation-type (plist-get object :relation_type))
	 (delay (plist-get object :delay))
	 ;; plist should not have the :issue_id element.
	 ;; If not, redmine returns 500 error.
	 (plist (list :issue_to_id issue-to-id
		      :relation_type relation-type)))
    (and delay (setq plist (plist-put plist :delay delay)))
    (elmine/api-post :relation plist
                     (format "/issues/%s/relations.json" issue-id))))

(defalias 'elmine/create-relation 'orgmine/create-relation)

(defun orgmine/delete-relation (id)
  "Delete an relation with a specific id."
  (elmine/api-delete (format "/relations/%s.json" id)))

(defalias 'elmine/delete-relation 'orgmine/delete-relation)

(defun orgmine/api-raw2 (method path data params)
  "Perform a raw HTTP request with given METHOD, a relative PATH and a
plist of PARAMS for the query."
  (let* ((redmine-host (if (boundp 'redmine-host)
                           redmine-host
                         elmine/host))
         (redmine-api-key (if (boundp 'redmine-api-key)
                              redmine-api-key
                            elmine/api-key))
         (url (elmine/api-build-url path params))
         (url-request-method method)
         (url-request-extra-headers
;;           `(("Content-Type" . "application/json")
          `(("Content-Type" . "application/octet-stream")
            ("X-Redmine-API-Key" . ,redmine-api-key)))
         (url-request-data data)
         header-end status header body)
    (save-excursion
      (switch-to-buffer (url-retrieve-synchronously url))
      (beginning-of-buffer)
      (setq header-end (save-excursion
                         (if (re-search-forward "^$" nil t)
                             (progn
                               (forward-char)
                               (point))
                           (point-max))))
      (when (re-search-forward "^HTTP/\\(1\\.0\\|1\\.1\\) \\([0-9]+\\) \\([A-Za-z ]+\\)$" nil t)
        (setq status (plist-put status :code (string-to-number (match-string 2))))
        (setq status (plist-put status :text (match-string 3))))
      (while (re-search-forward "^\\([^:]+\\): \\(.*\\)" header-end t)
        (setq header (cons (match-string 1) (cons (match-string 2) header))))
      (unless (eq header-end (point-max))
        (setq body (url-unhex-string
                    (buffer-substring header-end (point-max)))))
      (kill-buffer))
    `(:status ,status
      :header ,header
      :body ,body)))

(defalias 'elmine/api-raw2 'orgmine/api-raw2)

(defun orgmine/api-post2 (data path &rest params)
  "Does an http POST request and returns response status as symbol."
  (let* ((params (if (listp (car params)) (car params) params))
         (response (elmine/api-raw2 "POST" path data params))
         (object (elmine/api-decode (plist-get response :body))))
    object))

(defalias 'elmine/api-post2 'orgmine/api-post2)

(defun orgmine/upload-file (file)
  "upload a specific file to Redmine for the attachment."
  (let ((data (with-temp-buffer
		(insert-file-contents-literally file)
		(buffer-string))))
    (elmine/api-post2 data "/uploads.json")))

(defalias 'elmine/upload-file 'orgmine/upload-file)

(defun orgmine/get-project-wiki-pages (project &rest filters)
  "Get a list of wiki pages for a specific project."
  (apply #'elmine/api-get-all :wiki_pages
         (format "/projects/%s/wiki/index.json" project) filters))

(defalias 'elmine/get-project-wiki-pages 'orgmine/get-project-wiki-pages)

(defun orgmine/get-wiki-page (project title)
  "Get a specific wiki page via project and title."
  (elmine/api-get :wiki_page
		  (format "/projects/%s/wiki/%s.json" project title)
		  :include "attachments"))

(defalias 'elmine/get-wiki-page 'orgmine/get-wiki-page)

(defun orgmine/update-wiki-page (project title &rest params)
  "Create or update a specific wiki page via project and title."
  (let ((object (if (listp (car params)) (car params) params)))
    (elmine/api-put :wiki_page object
		    (format "/projects/%s/wiki/%s.json" project title))))

(defalias 'elmine/update-wiki-page 'orgmine/update-wiki-page)

(defun elmine/delete-wiki-page (project title)
  "Delete a specific wiki page entry."
  (elmine/api-delete (format "/projects/%s/wiki/%s.json" project title)))

(defalias 'elmine/delete-wiki-page 'orgmine/delete-wiki-page)



(defun orgmine-server (base-url)
  "Return the server entry of the Redmine server in `orgmine-servers'
whose host is BASE-URL."
  (catch 'found
    (mapc (lambda (elem)
            (let ((host (cdr (assoc 'host (cdr elem)))))
              (if (string= host base-url)
                  (throw 'found elem))))
          orgmine-servers)))

(defun orgmine-parse-issue-url (url)
  "Parse URL and return a cons (SERVER . ISSUE-ID)."
  (save-match-data
    (if (string-match "^\\(http.*\\)/issues/\\([0-9]+\\)" url)
        ;; redmine url -> orgmine
        (let* ((base-url (match-string 1 link))
               (issue-id (match-string 2 link))
               (server (orgmine-server base-url)))
          (if server
              (cons (car server) issue-id))))))

(defun orgmine-issue-buffer (server issue-id &optional title)
  "Create an orgmine issue buffer."
  (let* ((bufname (format "*OrgMine-%s:issues/%s*" server issue-id))
         (buf (get-buffer-create bufname)))
    (switch-to-buffer buf)
    (erase-buffer)
    (if title (insert (format "#+TITLE: %s\n" title)))
    (insert (format "#+PROPERTY: om_server %s\n\n" server))
    (set-buffer-file-coding-system 'utf-8)
    (org-mode)
    (orgmine-mode t)
    (save-excursion
      (orgmine-insert-issue issue-id))
    (hide-subtree)
    (show-branches)
    (org-align-all-tags)
    (set-buffer-modified-p nil)
    (run-hooks 'orgmine-issue-buffer-hook)
    (message "Editing issue #%s on %s" issue-id server)))

(defun orgmine-tag (key)
  "Return tag."
  (cdr (assoc key orgmine-tags)))

(defun orgmine-setup-custom-fields (config)
  (set (make-local-variable 'orgmine-custom-fields) nil)
  (mapc (lambda (plist)
	  (let ((name (orgmine-custom-field-property-name plist)))
	    (add-to-list 'orgmine-custom-fields (cons name plist))))
	config))

(defun orgmine-setup-tags ()
  (mapc (lambda (elem)
	  (let* ((key (car elem))
		 (value (cdr elem))
		 (symbol (intern (format "orgmine-tag-%s" key))))
	    (set (make-local-variable symbol) value)))
	orgmine-tags))

(defvar orgmine-valid-variables
  '(host api-key issue-title-format journal-title-format version-title-format
	 tracker-title-format project-title-format wiki-page-title-format
	 user-name-format custom-fields default-todo-keyword))

(defun orgmine-setup ()
  "Setup buffer local variables from ORGMINE-SERVERS per om_server property."
  (let* ((server (cdr (assoc-string "om_server" org-file-properties t)))
	 (config (cdr (assoc-string server orgmine-servers t))))
    (if config
	(set (make-local-variable 'orgmine-server) server))
    (mapc (lambda (elem)
	    (let* ((key (car elem))
		   (fmt (if (memq key '(host api-key))
			    "elmine/%s" "orgmine-%s"))
		   (symbol (intern (format fmt key)))
		   (value (cdr elem)))
	      (if (memq key orgmine-valid-variables)
		  (progn
		    (set (make-local-variable symbol) value)
		    (if (eq key 'custom-fields)
			(orgmine-setup-custom-fields value)))
		(message "orgmine-setup: %s: skipped - invalid name" key))))
	  config))
  (orgmine-setup-tags)
  (run-hooks 'orgmine-setup-hook))

(defvar orgmine-mode-map (make-sparse-keymap)
  "Keymap for `orgmine-mode', a minor mode.")

(define-minor-mode orgmine-mode
  "minor mode for org-mode with Redmine integration"
  :lighter "Mine" :keymap orgmine-mode-map
  (org-load-modules-maybe)
  (orgmine-setup)
  (set (make-local-variable 'orgmine-statuses) nil)
  (make-local-variable 'org-tags-exclude-from-inheritance)
  (if (and orgmine-journal-details-drawer
	   (boundp 'org-drawers))
      (add-to-list 'org-drawers orgmine-journal-details-drawer))
  (mapc (lambda (tag)
	  (add-to-list 'org-tags-exclude-from-inheritance tag))
	(list orgmine-tag-update-me orgmine-tag-create-me
	      orgmine-tag-project orgmine-tag-tracker
	      orgmine-tag-versions orgmine-tag-version
	      orgmine-tag-issue
	      orgmine-tag-description orgmine-tag-journals orgmine-tag-journal
	      orgmine-tag-wiki orgmine-tag-attachments))
  (define-key orgmine-mode-map "\C-cma" 'orgmine-add-attachment)
  (define-key orgmine-mode-map "\C-cmA" 'orgmine-insert-all-versions)
  (define-key orgmine-mode-map "\C-cmc" 'orgmine-submit)
  (define-key orgmine-mode-map "\C-cmd" 'orgmine-add-description)
  (define-key orgmine-mode-map "\C-cme" 'orgmine-ediff)
  (define-key orgmine-mode-map "\C-cmf" 'orgmine-fetch)
  (define-key orgmine-mode-map "\C-cmg" 'orgmine-goto-issue)
  (define-key orgmine-mode-map "\C-cmG" 'orgmine-goto-version)
  (define-key orgmine-mode-map "\C-cmi" 'orgmine-add-issue)
  (define-key orgmine-mode-map "\C-cmI" 'orgmine-insert-issue)
  (define-key orgmine-mode-map "\C-cmj" 'orgmine-add-journal)
  (define-key orgmine-mode-map "\C-cmk" 'orgmine-skeletonize-subtree)
  (define-key orgmine-mode-map "\C-cmp" 'orgmine-add-project)
  (define-key orgmine-mode-map "\C-cmP" 'orgmine-insert-project)
  (define-key orgmine-mode-map "\C-cms" 'orgmine-sync-subtree-recursively)
  (define-key orgmine-mode-map "\C-cmS" 'orgmine-sync-buffer)
  (define-key orgmine-mode-map "\C-cmT" 'orgmine-insert-tracker)
  (define-key orgmine-mode-map "\C-cmu" 'orgmine-goto-parent-issue)
  (define-key orgmine-mode-map "\C-cmv" 'orgmine-add-version)
  (define-key orgmine-mode-map "\C-cmV" 'orgmine-insert-version)
  (define-key orgmine-mode-map "\C-cmw" 'orgmine-add-wiki-page)
  (define-key orgmine-mode-map "\C-cmW" 'orgmine-insert-wiki-page)
  (define-key orgmine-mode-map "\C-cm\C-w" 'orgmine-refile)
  (define-key orgmine-mode-map "\C-cm#" 'orgmine-insert-template)
  (define-key orgmine-mode-map "\C-cm;;" 'orgmine-set-entry-property)
  (define-key orgmine-mode-map "\C-cm;a" 'orgmine-set-assigned-to)
  (define-key orgmine-mode-map "\C-cm;c" 'orgmine-set-custom-field)
  (define-key orgmine-mode-map "\C-cm;d" 'orgmine-set-done-ratio)
  (define-key orgmine-mode-map "\C-cm;t" 'orgmine-set-tracker)
  (define-key orgmine-mode-map "\C-cm;v" 'orgmine-set-version)
  (define-key orgmine-mode-map "\C-cm/a" 'orgmine-show-assigned-to)
  (define-key orgmine-mode-map "\C-cm/c" 'orgmine-show-child-issues)
  (define-key orgmine-mode-map "\C-cm/d" 'orgmine-show-descriptions)
  (define-key orgmine-mode-map "\C-cm/i" 'orgmine-show-issues)
  (define-key orgmine-mode-map "\C-cm/j" 'orgmine-show-journals)
  (define-key orgmine-mode-map "\C-cm/m" 'orgmine-show-assigned-to-me)
  (define-key orgmine-mode-map "\C-cm/n" 'orgmine-show-notes)
  (define-key orgmine-mode-map "\C-cm/p" 'orgmine-show-projects)
  (define-key orgmine-mode-map "\C-cm/r" 'orgmine-show-all)
  (define-key orgmine-mode-map "\C-cm/t" 'orgmine-show-trackers)
  (define-key orgmine-mode-map "\C-cm/u" 'orgmine-show-create-or-update)
  (define-key orgmine-mode-map "\C-cm/v" 'orgmine-show-versions)
  (define-key orgmine-mode-map "\C-cm?" 'orgmine-ediff)
  (add-hook 'org-after-todo-state-change-hook 'orgmine-after-todo-state-change)
  )


(defun orgmine-insert-demoted-heading (&optional title tags-list)
  "Insert a demoted headling at the beginning of the current line."
  (move-beginning-of-line nil)
  (if (save-match-data
	(or (looking-at "^\\*+ ") (eobp)))
      (open-line 1))
  (outline-insert-heading)
  (org-do-demote)
  (insert (or title ""))
  (mapc (lambda (tag)
	  (org-toggle-tag tag 'on))
	tags-list))

(defun orgmine-idname-to-id (idname &optional for-filter)
  ;; "ID:NAME" -> "ID"
  (save-match-data
    (cond ((string-match "^[0-9]+" idname)
	   (match-string 0 idname))
	  ((and for-filter
		(string-match "^!?\\*" idname)) ; "*" and "!*" for filter.
	   (match-string 0 idname)))))

(defun orgmine-redmine-date (date)
  ;; "[2011-03-02 Wed]" -> "2011-03-02"
  (save-match-data
    (if (string-match "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}" date)
	(match-string 0 date)
      "")))

(defun orgmine-org-date (date)
  ;; "2011-03-02" -> "[2011-03-02 Wed]"
  (condition-case nil
      (let ((time (apply 'encode-time (org-parse-time-string date))))
	(format-time-string (org-time-stamp-format nil t) time))
    (error "")))

(defun orgmine-tz-org-date (time-string)
  ;; "2015-08-07T02:55:08Z" -> "[2015-08-07 Fri 11:55]"
  (save-match-data
    (let* ((time-vector (timezone-fix-time time-string nil nil))
	   (time (apply 'encode-time
			(cdr (nreverse (append time-vector nil))))))
      (format-time-string (org-time-stamp-format t t) time))))

(defun orgmine-format-value (plist key)
  ;; author.name extract value of (:author (:name NAME))
  (save-match-data
    (let ((key-list (org-split-string key "\\."))
	  (value plist))
      (mapc (lambda (k)
	      (setq value (plist-get value (intern (format ":%s" k)))))
	    key-list)
      value)))

(defun orgmine-format (string plist)
  (with-temp-buffer
    (insert string)
    (goto-char (point-min))
    (while (re-search-forward "%{\\([^}]+\\)}" nil t)
;;       (let* ((key (intern (format ":%s" (match-string 1))))
;; 	     (value (plist-get plist key)))
      (let* ((key-str (match-string 1))
	     (key (intern (format ":%s" key-str)))
	     (value (orgmine-format-value plist key-str)))
	(cond ((member key '(:created_on :updated_on :closed_on))
	       (setq value (orgmine-tz-org-date value))))
	(replace-match (elmine/ensure-string value) t t)))
    (buffer-string)))

(defun orgmine-extract-subject (title)
  (save-match-data
    (if (string-match orgmine-title-format-regexp title)
	(match-string 1 title)
      title)))

(defun orgmine-map-region (func beg end &optional only-same-level)
  "Call FUNC for every heading between BEG and END."
  (let ((next-heading-func
	 (if only-same-level 'outline-get-next-sibling 'outline-next-heading))
	level)
    (save-excursion
      (setq end (copy-marker end))
      (goto-char beg)
      (if (outline-on-heading-p t)
	  (funcall func))
      (while (and (progn
		    (funcall next-heading-func)
		    (< (point) end))
		  (not (eobp)))
	(funcall func))
      (set-marker end nil))))

(defun orgmine-tags-in-tag-p (tags1 tags2)
  (catch 'found
    (mapc (lambda (tag)
	    (if (member tag tags2)
		(throw 'found tag)))
	  tags1)
    nil))

;;;
(defun orgmine-find-headline (tag &optional end only-same-level)
  "Search forward from point for headline with TAG
within the region between the current position and END.
If found, returns the beginning position of the headline."
  (let* ((pred (cond ((stringp tag) 'member)
		     ((listp tag) 'orgmine-tags-in-tag-p)))
	 (pos (catch 'found
		(orgmine-map-region (lambda ()
				      (if (funcall pred tag (org-get-tags))
					  (throw 'found (point))))
				    (point) (or end (point-max))
				    only-same-level)
		nil)))
    (if pos (goto-char pos))))

(defun orgmine-find-headline-prop (tag key value &optional end)
  "Search forward from point for headline with TAG and property of KEY is VALUE.
within the region between the current position and END.
If found, returns the beginning position of the headline."
    (let* ((value-regexp (if (orgmine-id-property-p key)
			     (format "%s\\(:?:.*\\)?" (regexp-quote value))
			   (regexp-quote value)))
	   (name (orgmine-property-name key))
	   (property-regexp (format "^[ \t]*:%s:[ \t]+%s[ \t]*$"
				    (regexp-quote name) value-regexp)))
      (catch 'found
	(while (re-search-forward property-regexp end t)
	  (let ((pos (point))
		(tags (progn
			(outline-previous-heading)
			(org-get-tags))))
	    (if (and (member tag tags)
		     (equal (nth 1 (orgmine-get-property nil key)) value))
		(throw 'found (point)))
	    (goto-char pos)))
	nil)))

(defun orgmine-find-headline-ancestor (tag &optional no-error)
  "Find a headline with TAG going back to ancestor headlines.
Return org-element data of the headline found.
If not found and NO-ERROR, return nil.  Otherwise, raise an error."
;; +Set point to the beginning of the headline found and return non-nil.+
  (org-with-wide-buffer
   (unless (eq (org-element-type (org-element-at-point)) 'headline)
     (outline-previous-heading))
   (catch 'found
     (let (no-more-ancestor)
       (while (not no-more-ancestor)
	 (let ((element (org-element-at-point)))
	   (cond ((member tag (org-element-property :tags element))
		  (throw 'found element))
		 ((<= (funcall outline-level) 1)
		  (setq no-more-ancestor t)) ; not found
		 (t (outline-up-heading 1))))))
     (unless no-error
       (error "No redmine %s headline found" tag)))))

(defun orgmine-delete-headline (tag &optional end only-same-level)
  "Search forward from point for headline with TAG
within the region between the current position and END.
If the headline is found, delete the subtree of the headline."
  (save-excursion
    (while (orgmine-find-headline tag end only-same-level)
      (let ((region (orgmine-subtree-region)))
        (delete-region (car region) (cdr region)))
      (outline-next-heading))))

(defun orgmine-note (headline)
  "return note in src-block element."
  (save-excursion
    (save-restriction
      (let ((start (org-element-property :begin headline)))
	(goto-char start)
	(outline-next-heading)
	(narrow-to-region start (point))
	(let* ((tree (org-element-parse-buffer))
	       (src-block (org-element-map tree 'src-block 'identity nil t)))
	  (org-element-property :value src-block))))))

(defun orgmine-um-headline (beg end tag)
  "return headlines with :UPDATE_ME: tag."
  (save-excursion
    (goto-char beg)
    (let ((headline))
      (while (orgmine-find-headline orgmine-tag-update-me end t)
	(let ((tags (org-get-tags)))
	  (cond ((member tag tags)
		 (if headline
		     (error "More than one %s headlines for an entry." tag)
		   (setq headline (org-element-at-point))))
		((or (member orgmine-tag-description tags)
		     (member orgmine-tag-attachments tags)
		     (member orgmine-tag-journal tags)
		     (member orgmine-tag-issue tags)
		     (member orgmine-tag-version tags)
		     (member orgmine-tag-tracker tags)
		     (member orgmine-tag-project tags)
		     (member orgmine-tag-wiki tags))) ; just ignore
		(t (error "invalid headline %s for :UPDATE_ME: tag." tag))))
;; 	(outline-next-heading))
	(outline-get-next-sibling))
      headline)))

(defun orgmine-parse-attachments-plain-list (element)
  "Parse plain list of attachments to upload.
Return list of plist (:path PATH :filename FILENAME :description DESCRIPTION)."
  (if (not element)
      nil
    (save-excursion
      (goto-char (org-element-property :begin element))
      (let* ((end (cdr (orgmine-subtree-region)))
	     (plain-link-regexp "file:\\([^ \t\n]+\\)\\(?:::[^ \t\n]+\\)")
	     (bracket-link-regexp
	      (concat "\\[\\[\\(?:file:\\([^][]+\\)"
		      "\\(?:::\\(?:[^][]+\\)\\)?\\)\\]"
		      "\\(?:\\[\\([^][]+\\)\\]\\)?\\]"))
	     attachments)
	(while (re-search-forward "^[ \t]*[+*-] +" end t)
	  (let ((plist
		 (cond ((looking-at plain-link-regexp)
			(let* ((path (match-string-no-properties 1))
			       (filename (file-name-nondirectory path)))
			  (list :path path :filename filename)))
		       ((looking-at bracket-link-regexp)
			(let* ((path (match-string-no-properties 1))
			       (filename (file-name-nondirectory
					  (or (match-string-no-properties 2)
					      path))))
			  (list :path path :filename filename))))))
	    (when plist
	      (goto-char (match-end 0))
	      (if (looking-at "[ \t]*\\(.+\\)[ \t]*$")
		  (let ((description (match-string-no-properties 1)))
		    (setq plist (plist-put plist :description description))))
	      (add-to-list 'attachments plist t))))
	attachments))))

(defun orgmine-um-headlines (beg end)
  "return headlines with :UPDATE_ME: tag.
Return value: (DESCRIPTION JOURNAL ATTACHMENTS)"
  (save-excursion
    (let* ((description (orgmine-um-headline beg end orgmine-tag-description))
	   (attachments (orgmine-parse-attachments-plain-list
			 (orgmine-um-headline beg end orgmine-tag-attachments)))
	   (journals (progn
		       (goto-char beg)
		       (orgmine-find-headline orgmine-tag-journals end t)))
	   (journal (and journals
			 (goto-char journals)
			 (org-goto-first-child)
			 (orgmine-um-headline (point) end
					      orgmine-tag-journal))))
      (list description journal attachments))))

(defun orgmine-current-issue-heading (&optional no-error)
  "Move to the beginning of the current issue headline."
  (let ((issue (orgmine-find-headline-ancestor orgmine-tag-issue no-error)))
    (when issue
      (goto-char (org-element-property :begin issue))
      issue)))

(defun orgmine-current-entry-heading (&optional no-error)
  "Move to the beginning of current entry headline
or move to current issuen headline."
  (condition-case err
      (org-back-to-heading)
    (error (unless no-error (error (nth 1 err)))))
  (let ((tags (org-get-tags)))
    (cond ((or (member orgmine-tag-project tags)
	       (member orgmine-tag-tracker tags)
	       (member orgmine-tag-version tags)
	       (member orgmine-tag-wiki tags))
	   (org-element-at-point))
	  (t (orgmine-current-issue-heading no-error)))))

(defun orgmine-property-name (key)
  "Convert Redmine REST API property name to org-mode property name."
  (format "om_%s" key))

(defun orgmine-prop (property)
  ;; "trcker" -> :tracker_id
  (intern (format (if (orgmine-id-property-p property)
                      ":%s_id" ":%s")
                  property)))

(defun orgmine-name (plist &optional format escape)
  (let ((name (if format
		  (orgmine-format format plist)
		(plist-get plist :name))))
    (if (and name escape)
	(replace-regexp-in-string " " "\\\\ " name)
      name)))

(defun orgmine-idname (plist &optional format escape)
  ;; plist -> "ID:NAME"
  (let ((id (plist-get plist :id))
	(name (orgmine-name plist format escape)))
    (cond ((and id name)
           (format "%s:%s" id name))
          (id
           (elmine/ensure-string id)))))

(defun orgmine-delete-properties (pom regexp)
  "Delete entry properties at POM which match REGEXP."
  (let ((properties (orgmine-entry-properties pom 'all)))
    (save-match-data
      (mapc (lambda (prop)
	      (let ((property (car prop)))
		(if (string-match regexp property)
;; 		    (org-delete-property property))))
		    (org-entry-delete nil property))))
	    properties))))

(defun orgmine-custom-field-property-name (plist)
  ;; (:value "3" :name "Owner" :id 1) -> "om_cf_1_Owner"
  (format "om_cf_%s_%s"
	  (plist-get plist :id) (plist-get plist :name)))

(defun orgmine-custom-field-plist (property-name)
  ;; "om_cf_1_Owner" -> (:name "Owner" :id 1)
  (save-match-data
    (if (string-match "^om_cf_\\([0-9]+\\)_\\(.*\\)" property-name)
	(list :name (match-string 2 property-name)
	      :id (match-string 1 property-name)))))

(defun orgmine-set-properties-custom-fields (custom-fields)
  ;; ((:value \"3\" :name \"Owner\" :id 1))
  ;; erase "oc_cf_*" properties.
  (orgmine-delete-properties nil "^om_cf_")
  (mapc (lambda (cf-plist)
	  (let* ((name (orgmine-custom-field-property-name cf-plist))
		 (value (plist-get cf-plist :value))
		 (str-value (if (listp value)
				(mapconcat 'org-entry-protect-space value " ")
			      (org-entry-protect-space
			       (elmine/ensure-string value)))))
	    (if (and value (> (length str-value) 0))
		(org-set-property name str-value))))
	custom-fields))

(defvar orgmine-relations
  '(("duplicates" . "duplicated")
    ("blocks" . "blocked")
    ("precedes" . "follows")
    ("copied_to" . "copied_from")))

(defun orgmine-relation-property-type (plist &optional my-id)
  (let ((type (plist-get plist :relation_type))
	(issue-to-id (plist-get plist :issue_to_id)))
    (if (equal my-id issue-to-id)
	(or (cdr (assoc type orgmine-relations))
	    (car (rassoc type orgmine-relations))
	    type)
      type)))

(defun orgmine-relation-property-name (plist &optional my-id)
  ;; (:relation_type "precedes" :issue_to_id 10 :delay 0 :id 1234)
  ;;   -> "om_relation_1234_precedesr"
  (let ((type (orgmine-relation-property-type plist my-id))
	(id (plist-get plist :id)))
    (format "om_relation_%s_%s" id type)))

(defun orgmine-relation-property-value (plist &optional my-id)
  (let* ((type (orgmine-relation-property-type plist my-id))
	 (issue-to-id (plist-get plist :issue_to_id))
	 (other-id (elmine/ensure-string (if (equal my-id issue-to-id)
					     (plist-get plist :issue_id)
					   issue-to-id)))
	 (delay (plist-get relation :delay)))
    (if (and (member type '("precedes" "follows")) delay)
	(format "%s/d%s" other-id delay)
      other-id)))

(defun orgmine-relation-plist (property &optional my-id)
  ;; "om_relation_1234_precedes" -> (:relation_type "precedes" :id 1234)
  (save-match-data
    (let ((name (car property))
	  (value (cdr property))
	  plist)
      (if (string-match "^om_relation_\\(?:\\([0-9]+\\)_\\)?\\(.*\\)" name)
	  (let ((id (match-string 1 name))
		(type (match-string 2 name)))
	    (if type
		(progn (setq plist (list :relation_type type))
		       (if id (setq plist (plist-put plist :id id)))))))
      (if (and plist
	       (string-match "^\\([0-9]+\\)\\(?:/d\\([0-9]+\\)\\)?" value))
	  (let* ((other-id (match-string 1 value))
		 (delay (match-string 2 value)))
	    (setq plist (plist-put plist :issue_to_id other-id))
	    (if my-id (setq plist (plist-put plist :issue_id my-id)))
	    (if delay (setq plist (plist-put plist :delay delay)))))
      plist)))

(defun orgmine-set-properties-relations (relations redmine-issue)
  (orgmine-delete-properties nil "^om_relation_")
  (let ((id (plist-get redmine-issue :id)))
    (mapc (lambda (relation)
	    (let* ((name (orgmine-relation-property-name relation id))
		   (value (orgmine-relation-property-value relation id)))
	      (org-set-property name value)))
	  relations)))

(defun orgmine-set-properties (type redmine-issue property-list)
  "Set properties to the current headline per REDMINE-ISSUES.
Only the properties provided in PROPERTY-LIST are updated."
  (mapc (lambda (key)
	  (let* ((name (orgmine-property-name key))
		 (prop (intern (format ":%s" key)))
;; 		 (prop (orgmine-prop key))
		 (value (cond ((and (eq key type)
                                    (orgmine-idname redmine-issue)))
                              (t (plist-get redmine-issue prop)))))
	    ;; TODO: timestamp conversion:
	    ;;       yyyy-mm-dd -> [yyyy-mm-dd xxx]
	    (cond ((eq key 'custom_fields)
		   (orgmine-set-properties-custom-fields value))
		  ((eq key 'relations)
		   (orgmine-set-properties-relations value redmine-issue))
		  ((null value)
		   (org-entry-delete nil name))
		  ((listp value)	; '(:name NAME :id ID)
		   (org-set-property name (orgmine-idname value)))
		  ;; XXX: second info will be lost if converting to
		  ;; org-mode timestamp, hh:mm:ss -> hh:mm
;; 		  ((member prop '(:created_on :updated_on :closed_on))
;; 		   (org-set-property name (orgmine-tz-org-date value)))
		  ((member prop '(:start_date :due_date))
		   (org-set-property name (orgmine-org-date value)))
		  (t
		   (org-set-property name (elmine/ensure-string value))))))
	property-list))

(defvar orgmine-id-properties '(project assigned_to tracker fixed_version)
  "redmine property names whose value is plist of (:id ID :name NAME).")

(defun orgmine-id-property-p (property)
  "Non-nil if PROPERTY is a redmine ID property whose value is
a plist of (:id ID :name NAME)."
  (memq property orgmine-id-properties))

(defun orgmine-entry-properties (&optional pom which)
  "Workaround for old `org-entry-properties' that cannot get properties
from the headline property drawer."
  (condition-case err
      (org-entry-properties pom which "")
    (error
     (if (eq (car err) 'wrong-number-of-arguments)
	 (org-entry-properties pom which)))))

(defun orgmine-get-property-custom-fields (pom &optional properties)
  (or properties
      (setq properties (orgmine-entry-properties pom 'all)))
  (let (custom-fields)
    (mapc (lambda (property)
	    (let* ((name (car property))
		   (plist (orgmine-custom-field-plist name)))
	      (if (and plist
		       (not (orgmine-plist-list-get custom-fields
						    :id (plist-get plist :id))))
		  (let* ((props (cdr (assoc-string name orgmine-custom-fields
						   t)))
			 (value (cdr property)))
		    (if (plist-get props :multiple)
			(setq value (mapcar 'org-entry-restore-space
					    (org-split-string value "[ \t]")))
		      (setq value (org-entry-restore-space value)))
		    (add-to-list 'custom-fields
				 (nconc plist (list :value value)))))))
	  properties)
;;     custom-fields))
    (if custom-fields
	;; workaround for `json-enconde-list', which wrongly handles
	;; list of plist as alist.
	(add-to-list 'custom-fields nil t))))

(defun orgmine-relation-value-plist (value &optional my-id)
  ;; "123/d3" -> (:issue_to_id 123 :delay 3)
  ;; "444" -> (:issue_to_id 444)
  (save-excursion
    (if (string-match "^\\([0-9]+\\)\\(?:/d\\([0-9]+\\)\\)?" value)
	(let* ((other-id (match-string 1 value))
	       (delay (match-string 2 value))
	       (plist (cond ((null my-id)
			     (list :issue_to_id other-id))
			    ((equal my-id other-id)
			     (list :issue_to_id my-id :issue-id other-id))
			    (t
			     (list :issue_to_id other-id :issue-id my-id)))))
	  (if delay
	      (plist-put plist :delay delay)
	    plist)))))

(defun orgmine-get-property-relations (pom &optional properties)
  (or properties
      (setq properties (orgmine-entry-properties pom 'all)))
  (let* ((issue (orgmine-find-headline-ancestor orgmine-tag-issue t))
	 (beg (org-element-property :begin issue))
	 (id (orgmine-get-id beg))
	 relations)
    (if issue
	(mapc (lambda (property)
		(let* ((plist (orgmine-relation-plist property id)))
		  (if plist
		      (add-to-list 'relations plist))))
	      properties))
    ;; (if relations
;; 	;; workaround for `json-enconde-list', which wrongly handles
;; 	;; list of plist as alist.
;; 	(add-to-list 'relations nil t))
    relations))

(defun orgmine-get-property (pom property
				 &optional properties inherit for-filter)
  (cond
   ((eq property 'custom_fields)
    (let ((custom-fields (and (boundp 'orgmine-custom-fields)
                              (orgmine-get-property-custom-fields pom))))
      (if custom-fields (list :custom_fields custom-fields))))
   ((eq property 'relations)
    (let ((relations (orgmine-get-property-relations pom)))
      (if relations (list :relations relations))))
   (t
    (let* ((name (orgmine-property-name property)) ; 'id -> "om_id" and so on
	   (id-property-p (orgmine-id-property-p property))
	   (prop (intern (format (if id-property-p ":%s_id" ":%s")
				 property)))
	   (value (if (or inherit (not properties))
		      (save-restriction
;; 			(widen)
;; 			(org-show-hidden-entry) ;XXX
			(org-entry-get pom name inherit))
;; 		    (or properties
;; 			(setq properties (orgmine-entry-properties pom 'all)))
		    (cdr (assoc-string name properties t)))))
      (if value
	  (let ((redmine-value
		 (cond (id-property-p
			(orgmine-idname-to-id value for-filter))
		       ((member prop '(:start_date :due_date))
			(orgmine-redmine-date value))
		       (t value))))
	    (list prop redmine-value)))))))

(defun orgmine-get-properties (pom property-list &optional inherit for-filter)
  "Get properties from the headline at point-or-maker POM.
Only the properties given by PROPERTY-LIST are retrieved."
  (let ((properties (unless inherit (orgmine-entry-properties pom 'all)))
	plist)
    (mapc (lambda (property)
	    (let ((list (orgmine-get-property pom property
					      properties inherit for-filter)))
	      (if list
		  (setq plist (plist-merge plist list)))))
	  property-list)
    plist))

(defun orgmine-get-id (pom &optional id-prop properties)
  (or id-prop (setq id-prop 'id))
  (let* ((plist (orgmine-get-property pom id-prop properties))
	 (id (nth 1 plist)))
    id))

(defvar orgmine-statuses)

(defun orgmine-issue-status-id (name)
  ;; status name -> status id
  ;; TODO: cache statues
  (or orgmine-statuses (setq orgmine-statuses (elmine/get-issue-statuses)))
  (catch 'found
    (mapc (lambda (status)
	    (if (equal (plist-get status :name) name)
		(throw 'found (plist-get status :id))))
	  orgmine-statuses)))

(defun orgmine-subtree-region ()
  (save-excursion
    (cons (progn
	    (org-back-to-heading t)
	    (point))
	  (progn
	    (org-end-of-subtree t t)
;; 	    (if (and (org-at-heading-p) (not (eobp))) (backward-char 1))
	    (point)))))

(defun orgmine-entry-region ()
  "Returns the region from the beginning of headline to the next headline
as a cons cell (BEG . END)."
  (save-excursion
    (cons (progn
	    (org-back-to-heading t)
	    (point))
	  (progn
	    (outline-next-heading)
;; 	    (if (and (org-at-heading-p) (not (eobp))) (backward-char 1))
	    (if (org-at-heading-p) (backward-char 1))
	    (point)))))

(defun orgmine-body-region ()
  "Returns the region from the beginning of body to the next headline
as a cons cell (BEG . END)."
  (org-back-to-heading t)
  (show-subtree)
  (save-excursion
    (forward-line)
    (if (not (org-at-heading-p t))
        (cons (point)
              (or (outline-next-heading) (point-max))))))

(defun orgmine-default-todo-keyword ()
  "Returns the default TODO keyword for the initial status of Redmine issue.
The default TODO keyword can be specified by \"om_default_todo\" property,
such as \"#+PROPERTY: om_default_todo NEW\".
If the property is not found, the first TODO keyword of `org-todo-keywords-1'
is returned."
  (or (cdr (assoc-string "om_default_todo" org-file-properties))
      orgmine-default-todo-keyword
      (nth 0 org-todo-keywords-1)
      1))

(defun orgmine-todo (keyword)
  "Set the TODO state to KEYWORD."
  (let ((org-after-todo-state-change-hook
         org-after-todo-state-change-hook))
    (remove-hook 'org-after-todo-state-change-hook
                 'orgmine-after-todo-state-change)
    (org-todo keyword)))

(defun orgmine-collect-update-plist (issue &optional subject-prop)
  "collect updating entries and return them as plist"
  (or subject-prop (setq subject-prop :subject))
  (org-with-wide-buffer
   (goto-char (org-element-property :begin issue))
   ;; XXX: TODO: restrict range to subtree.
   (let* ((beg (point))
	  (end (cdr (orgmine-subtree-region)))
;; 	  (um-headlines (orgmine-um-headlines beg end))
	  (um-headlines (and (org-goto-first-child)
			     (orgmine-um-headlines (point) end)))
	  (description (nth 0 um-headlines))
	  (journal (nth 1 um-headlines))
	  (attachments (nth 2 um-headlines)))
     (goto-char beg)
     (let* ((title (org-element-property :title issue))
	    (todo-keyword (org-element-property :todo-keyword issue))
	    (scheduled (org-entry-get nil "SCHEDULED"))
	    (deadline (org-entry-get nil "DEADLINE"))
	    (effort (org-entry-get nil org-effort-property)) ; "Effort"
	    (plist-inherit
	     (orgmine-get-properties nil '(tracker fixed_version project) t))
	    (plist
	     (orgmine-get-properties
	      nil '(id start_date due_date done_ratio assigned_to
;; 		       estimated_hours custom_fields) nil)))
		       estimated_hours custom_fields relations) nil)))
       (setq plist (plist-merge plist plist-inherit))
       (if title
	   (setq plist			; `subject-prop': :subject or :name
		 (plist-put plist subject-prop
			    (orgmine-extract-subject title))))
       (if todo-keyword
	   (let ((status-id (orgmine-issue-status-id todo-keyword)))
	     (setq plist (plist-put plist :status_id status-id))))
       (if scheduled
	   (setq plist
		 (plist-put plist :start_date
			    (orgmine-redmine-date scheduled))))
       (if deadline
	   (setq plist
		 (plist-put plist :due_date (orgmine-redmine-date deadline))))
       (if effort
	   (setq plist
		 (plist-put plist :estimated_hours
			    (/ (org-duration-string-to-minutes effort) 60))))
       (if description
	   (setq plist
		 (plist-put plist :description (orgmine-note description))))
       (if journal
	   (setq plist (plist-put plist :notes (orgmine-note journal))))
       (if attachments			; XXX
	   (setq plist (plist-put plist :attachments attachments)))
       plist))))

(defun orgmine-plist-list-get (plist-list key value)
  "Search for a plist in list of plist.
Return plist whose key is KEY and its value is equal to VALUE."
  (catch 'found
    (mapc (lambda (plist)
	    (let ((ret (plist-member plist key)))
	      (if (and (listp ret)
		       (equal (nth 1 ret) value))
		  (throw 'found plist))))
	  plist-list)
    nil))

(defun orgmine-get-issue (id &optional cache)
  "Get a redmine issue."
  (if (stringp id)
      (setq id (string-to-number id)))
  (if cache
      (orgmine-plist-list-get cache :id id)
    (elmine/get-issue-with-journals id)))

(defun orgmine-get-version (id &optional cache)
  "Get a redmine fixed version."
  (if (stringp id)
      (setq id (string-to-number id)))
  (if cache
      (orgmine-plist-list-get cache :id id)
    (elmine/get-version id)))

(defun orgmine-get-tracker (id &optional cache)
  "Get a redmine tracker."
  (if (stringp id)
      (setq id (string-to-number id)))
  (if cache
      (orgmine-plist-list-get cache :id id)
    (let ((trackers (elmine/get-trackers)))
      (orgmine-plist-list-get trackers :id id))))

(defun orgmine-get-project (id &optional cache)
  "Get a redmine project."
  (if (stringp id)
      (setq id (string-to-number id)))
  (if cache
      (or (orgmine-plist-list-get cache :identifier id)
	  (orgmine-plist-list-get cache :id id))
    (elmine/get-project id)))

;; TODO: make much more readable
(defun orgmine-pp-plist (plist &optional depth)
  (or depth (setq depth 0))
  (let ((count 0))
    (save-match-data
      (mapconcat
       (lambda (elem)
	 (prog1
	     (let* ((id-value-p
		     (and (listp elem)
			  (plist-get elem :id) (plist-get elem :value)))
		    (str (elmine/ensure-string elem))
		    (nl (string-match "\n" str)))
	       (cond (id-value-p
		      (format "    %s: %s\n"
			      (orgmine-idname elem) (plist-get elem :value)))
		     ((listp elem)
		      (format "\n%s" (orgmine-pp-plist elem (1+ depth))))
		     ((= (% count 2) 0) (format "%s%s:"
						(make-string (* depth 2) ? )
						str))
		     (nl (format "\n%s\n" str))
		     (t (format " %s\n" str))))
	   (setq count (1+ count))))
       plist ""))))

(defun orgmine-y-or-n-p (prompt plist)
  (save-window-excursion
    (switch-to-buffer-other-window "*ORGMINE PROPERTIY LIST*")
    (read-only-mode -1)
    (erase-buffer)
    (insert (orgmine-pp-plist plist))
    (goto-char (point-min))
    (set-buffer-modified-p nil)
    (read-only-mode)
    (message "plist: %s" plist)
    (prog1
	;; XXX: map-y-or-n-p -- see `save-some-buffers' for its usage
	(y-or-n-p prompt)
      (kill-buffer))))

(defun orgmine-pp-note (redmine-note indent)
  (save-match-data
    (if (string-match "\n\\'" redmine-note)
	(setq redmine-note (substring redmine-note 0
				      (1- (length redmine-note))))))
  (let ((leading (make-string indent ? )))
    (mapconcat (lambda (line)
		 (concat leading line))
	       (split-string redmine-note "\n") "\n")))

(defun orgmine-insert-note (note &optional force)
  (when (or force (> (length note) 0))
    (forward-line)
    (unless (bolp) (insert "\n"))
    (open-line 1)
    (insert orgmine-note-block-begin)	; "#+begin_src gfm"
    (org-indent-line)
    (let ((indent (org-get-indentation))
	  pos)
      (insert "\n")
      (setq pos (point))
      (org-indent-line)
      (insert orgmine-note-block-end)	; "#+end_src"
      (goto-char pos)
      (cond ((equal note "\n")
	     (open-line 1))
	    ((> (length note) 0)
	     (insert (orgmine-pp-note note (+ indent 2)) "\n"))))))

(defun orgmine-find-note-block ()
  "Return the note block of the current entry as cons of (BEG . END).
If the note block is not found, return nil."
  (save-excursion
    (let* ((region (orgmine-entry-region))
	   (beg (car region))
	   (end (cdr region))
	   (note-block-begin-regexp
	    (format "^[ \t]*%s" (regexp-quote orgmine-note-block-begin)))
	   (note-block-end-regexp
	    (format "^[ \t]*%s[ \t]*\n?" (regexp-quote orgmine-note-block-end))))
      (goto-char end)
      (catch 'found
	(while (re-search-backward note-block-begin-regexp beg t)
	  (let ((pos (point)))
	    (if (re-search-forward note-block-end-regexp end t)
		(throw 'found (cons pos (point))))))))))

(defun orgmine-journal-details-drawer-region (beg end)
  (save-excursion
    (goto-char beg)
    (let ((re (format "^[ \t]*:%s:[ \t]*$" orgmine-journal-details-drawer)))
      (if (re-search-forward re end t)
	  (let ((beg (match-beginning 0)))
	    (when (re-search-forward "^[ \t]*:END:.*" end t)
	      (cons beg (match-end 0))))))))

(defun orgmine-insert-journal-details (journal)
  (let* ((details (plist-get journal :details))
	 (region (orgmine-entry-region))
	 (beg (car region))
	 (end (cdr region)))
    (when details
      (org-back-to-heading t)
      (if (fboundp 'org-end-of-meta-data-and-drawers)
	  (org-end-of-meta-data-and-drawers)
	(org-end-of-meta-data t))
      (when orgmine-journal-details-drawer
	(let* ((region (orgmine-journal-details-drawer-region beg end)))
	  (if region
	      (progn
		(delete-region (car region) (cdr region))
		(goto-char (car region)))
	    (open-line 1)))
	(if (looking-at org-outline-regexp)
	    (open-line 1))
	(org-indent-line)
	(insert ":" orgmine-journal-details-drawer ":\n")
	(org-indent-line)
	(insert ":END:")
	(move-beginning-of-line nil))
      (let ((pos (copy-marker (save-excursion
				(forward-line)
				(point)))))
	(mapc (lambda (plist)
		(open-line 1)
		(org-indent-line)
		(let ((old (plist-get plist :old_value))
		      (new (plist-get plist :new_value))
		      (name (plist-get plist :name))
		      (property (plist-get plist :property)))
		  (insert "- " property "_" name ": "
			  (cond ((or (equal name "description")
				     (and (stringp old) (string-match "\n" old))
				     (and (stringp new) (string-match "\n" new)))
				 "CHANGED")
				((and old new)
				 (format "\"%s\" -> \"%s\"" old new))
				(old (format "\"%s\" -> DELETED" old))
				(new (format "ADDED -> \"%s\"" new)))))
		(move-beginning-of-line nil))
	      details)
	(goto-char pos)
	(forward-line -1)
	(set-marker pos nil)))))

(defun orgmine-insert-journal (beg end journal issue-id count &optional force)
  (let* ((author (plist-get (plist-get journal :user) :name))
	 (journal-id (plist-get journal :id))
	 (journal (plist-merge journal
			       (list :id issue-id :count count
				     :author author :journal_id journal-id)))
	 (title (orgmine-format orgmine-journal-title-format journal)))
    (goto-char beg)
    (if (orgmine-find-headline-prop orgmine-tag-journal
				    'count (elmine/ensure-string count) end)
	(let ((region (orgmine-find-note-block)))
	  (if region
	      (progn
		(delete-region (car region) (cdr region))
		(goto-char (car region))
		(if (and (looking-at "^$") (not (eobp)))
		    (delete-char 1)))
	    (outline-next-heading))
	  (forward-line -1))
      (goto-char beg)
      (orgmine-insert-demoted-heading title (list orgmine-tag-journal)))
    (orgmine-insert-note (plist-get journal :notes) force)
    (orgmine-insert-journal-details journal)
;;     (orgmine-set-properties 'journal journal '(id count created_on user))
    (orgmine-set-properties 'journal journal '(count))))

(defun orgmine-find-journals (end &optional insert keep-subtree)
  "Find journals headline of the child entry of the current headline.
If the journals headline is not found and INSERT is non-nil,
the new entry will be inserted as the child entry of the current headline."
  (let ((beg (point)))
;;     (outline-next-heading)
    (org-goto-first-child)
    (if (orgmine-find-headline orgmine-tag-journals end t)
	(if keep-subtree
	    (outline-next-heading)
	  (let ((journal-end (cdr (orgmine-subtree-region))))
	    (forward-line)
	    (delete-region (point) journal-end)))
      (when insert
	(goto-char beg)
	(outline-next-heading)
	(orgmine-insert-demoted-heading "Journals"
					(list orgmine-tag-journals))
        (outline-next-heading)
	(if (and (markerp end)
		 (> (point) end))
	    (set-marker end (point)))))))

(defun orgmine-insert-journals (redmine-journals beg end)
  "Insert journals subtree between region from BEG to END.
If the journals headline already exits, the tree will be updated.
Otherwise, new tree will be inserted at BEG."
  (goto-char beg)
;;   (orgmine-find-journals end t nil)
  (orgmine-find-journals end t t)
  (save-excursion
    ;; remove journal headline with :UPDATE_ME: tag.
    (outline-previous-heading)
    (when (orgmine-find-headline-prop orgmine-tag-journal 'count "0" end)
      (let ((region (orgmine-entry-region)))
	(delete-region (car region) (cdr region)))))
  (let ((pos (point))
	(count 0))
    (mapc (lambda (journal)
	    (goto-char pos)
	    (orgmine-insert-journal pos end journal id
				    (setq count (1+ count))))
	  (reverse redmine-journals))))

(defun orgmine-insert-description (redmine-description beg end &optional force)
  "Insert description headline between region from BEG to END.
If the description headline already exits, the headline will be updated.
Otherwise, new tree will be inserted at BEG."
  (goto-char beg)
  (outline-next-heading)
  (if (orgmine-find-headline orgmine-tag-description end t)
      (progn
	(org-toggle-tag orgmine-tag-update-me 'off)
	(let ((region (orgmine-find-note-block)))
	  (if region
	      (progn
		(delete-region (car region) (cdr region))
		(goto-char (car region))
		(if (and (looking-at "^$") (not (eobp)))
		    (delete-char 1)))
	    (outline-next-heading))
	  (forward-line -1)))
    ;; insert description headline
    (orgmine-insert-demoted-heading "Description"
				    (list orgmine-tag-description)))
  (orgmine-insert-note redmine-description force))

(defun orgmine-insert-attachment (plist)
  (let ((description (plist-get plist :description)))
  (unless (looking-at "^$") (move-beginning-of-line nil) (open-line 1))
  (org-indent-line)
  (insert "- "
	  (orgmine-format orgmine-attachment-format plist))
  (when (and description (> (length description) 0))
    (insert "\n")
    (org-indent-line)
    (insert description))))

(defun orgmine-insert-attachments (redmine-attachments beg end &optional force)
  "Insert attachments headline between region from BEG to END.
If the attachments headline already exits, the headline will be updated.
Otherwise, new tree will be inserted at BEG."
  (goto-char beg)
  (outline-next-heading)
  (if (orgmine-find-headline orgmine-tag-attachments end t)
      (progn
	(org-toggle-tag orgmine-tag-update-me 'off)
	(let ((region (orgmine-subtree-region)))
	  (forward-line)
	  (delete-region (point) (cdr region))
	  (if (and (looking-at "^$") (not (eobp)))
	      (delete-char 1))))
    ;; insert attachments headline
    (orgmine-insert-demoted-heading "Attachments"
				    (list orgmine-tag-attachments))
    (forward-line))
  (mapc (lambda (redmine-attachment)
	  (save-excursion
	    (orgmine-insert-attachment redmine-attachment)))
	(reverse redmine-attachments)))

(defun orgmine-update-special-properties (redmine-issue)
  "Update the special properties per REDMINE-ISSUE."
  (let* ((status (plist-get redmine-issue :status)) ; version :status STATUS
	 (status-name (plist-get status :name))     ; issue (:id ID :name NAME)
	 (start-date (plist-get redmine-issue :start_date))
	 (due-date (plist-get redmine-issue :due_date))
	 (created-on (plist-get redmine-issue :created_on))
	 (closed-on (plist-get redmine-issue :closed_on))
	 (estimated-hours (plist-get redmine-issue :estimated_hours)))
    (if (equal status "closed")		; for version entry
	(org-toggle-tag org-archive-tag 'on)
      (org-toggle-tag org-archive-tag 'off))
    (if status-name			; for issue entry
        (orgmine-todo status-name))
    (if start-date			; SCHEDULED: prop
	(org-add-planning-info 'scheduled start-date)
      (org-remove-timestamp-with-keyword org-scheduled-string))
    (if due-date			; DEADLINE: prop
	(org-add-planning-info 'deadline due-date)
      (org-remove-timestamp-with-keyword org-deadline-string))
;;     (if (and (stringp closed-on) (stringp created-on)
;; 	     (string< created-on closed-on)) ; XXX
    (if (member status-name org-done-keywords)
	(org-add-planning-info 'closed (orgmine-tz-org-date closed-on))
      (org-add-planning-info nil nil 'closed))
    (if estimated-hours
	(org-set-property org-effort-property
			  (format "%sh" (elmine/ensure-string estimated-hours)))
      (org-entry-delete nil org-effort-property))))

(defun orgmine-entry-up-to-date-p (entry plist)
  "Returns non-nil if ENTRY is up-to-date comparing to Redmine's PLIST."
  (let* ((beg (org-element-property :begin entry))
	 (redmine-updated-on (plist-get plist :updated_on))
	 (updated-on (nth 1 (orgmine-get-property beg 'updated_on))))
    (and (stringp redmine-updated-on) (stringp updated-on)
	 (not (string< updated-on redmine-updated-on)))))

(defun orgmine-dirty-p (entry &optional plist)
  "Non-nil if the ENTRY (org-element data) is locally edited."
  (setq plist (or plist (orgmine-collect-update-plist entry)))
  (or (member orgmine-tag-update-me (org-element-property :tags entry))
      (plist-get plist :description) ; XXX: for issue only
      (plist-get plist :notes)	     ; XXX: for issue only
      (plist-get plist :attachments)))	; XXX: for issue only

(defun orgmine-update-title (title)
  "Update the title of the current headline."
  (unless (org-at-heading-p) (error "not on heading"))
  (save-excursion
    (let* ((org-special-ctrl-a/e t)
	   (beg (progn (move-beginning-of-line nil)
		       (org-beginning-of-line)
		       (point)))
	   (end (progn (move-end-of-line nil)
		       (org-end-of-line)
		       (point))))
      (if (< beg end)
	  (delete-region beg end))
      (goto-char beg)
      (insert title))))

(defun orgmine-update-entry (type entry plist
				  &optional force property-list extra)
  "Update ENTRY (org-element data) of TYPE per PLIST.
If the entry of Redmine is not updated since last sync and FORCE is nil,
the entry is not updated.
TYPE could be 'issue, 'fixed_version, 'tracker, and 'project.
Returns non-nil if the entry is updated."
  (let* ((beg (org-element-property :begin entry))
	 (idname (orgmine-idname plist))
	 ;; `title-format' is value of one of the following variable:
	 ;;     orgmine-issue-title-format, orgmine-version-title-format
	 ;;     orgmine-tracker-title-format, orgmine-project-title-format
	 (type0 (if (eq type 'fixed_version) 'version type))
	 (title-format (eval (intern (format "orgmine-%s-title-format" type0))))
	 (title (orgmine-format title-format plist)))
    (if (and (not force)
	     (orgmine-entry-up-to-date-p entry plist))
	(progn
	  (message "#%s: no change since last sync." idname)
	  nil)
      (if (and (not force)
	       (orgmine-dirty-p entry))
	  (error "#%s is locally edited.  Please submit change before updating."
		 idname))
      (message "Updating entry #%s ..." idname)
      (org-with-wide-buffer
       (goto-char beg)
       (let ((end (make-marker)))
	 (set-marker end (cdr (orgmine-subtree-region)))
	 (show-subtree)
	 (orgmine-update-title title)
	 (goto-char beg)
         (if (member orgmine-tag-update-me (org-get-tags))
             (org-toggle-tag orgmine-tag-update-me 'off))
	 (orgmine-set-properties type plist property-list)
	 ;; Update SCHEDULED:, DEADLINE:, TODO keyword, and CLOSED:
	 ;; per redmine properties.
	 (orgmine-update-special-properties plist)
	 ;; Update extra properties.
	 (if (functionp extra)
	     (funcall extra plist beg end))
	 (set-marker end nil)
	 (hide-subtree)))
      (message "Updating entry #%s ... done" idname))))

;;;;

(defun orgmine-submit-entry-update (entry id-prop subject-prop
					  orgmine-get-entry-func
					  orgmine-submit-entry-func
					  &optional force no-prompt)
  "Submit the entry update to Redmine."
  (org-save-outline-visibility t
    (show-branches)
    (let* ((plist (orgmine-collect-update-plist entry subject-prop))
 	   (id (plist-get plist id-prop)))	; XXX
      (unless id
	(error "No entry ID found at position %d"
	       (org-element-property :begin entry)))
      (setq plist (plist-merge plist (list :id id)))
      (if (or force
	      (orgmine-dirty-p entry plist))
	  (let* ((redmine-entry (funcall orgmine-get-entry-func id))
		 (up-to-date-p
		  (orgmine-entry-up-to-date-p entry redmine-entry)))
	    (if up-to-date-p
		(if (or no-prompt
			(orgmine-y-or-n-p
			 (format "Will you update entry #%s?" id) plist))
		    (funcall orgmine-submit-entry-func plist))
	      (if (not force)
		  (error "#%s: entry has been updated by other user." id)
		(if (yes-or-no-p
		     (format "#%s: entry has been updated by other user.
Will you force to update entry #%s? %s" id id plist))
		    (funcall orgmine-submit-entry-func plist)))))
	(message "#%s: no need to submit update." id)))))

(defun orgmine-submit-issue-relations (plist)
  "Create or delete issue relations per PLIST: (:relations relations)."
  (let ((relations (plist-get plist :relations))
	(issue-id (plist-get plist :id)))
    (if (and relations issue-id)
	(mapc (lambda (relation)
		(let* ((id (plist-get relation :id))
		       (issue-to-id (plist-get relation :issue_to_id)))
		  (setq relation (plist-merge relation
					      (list :issue_id issue-id)))
		  (cond ((and (null id) issue-to-id)
			 (elmine/create-relation relation))
			((and id (null issue-to-id))
			 (elmine/delete-relation id)))))
	      relations))))


(defun orgmine-upload-attachent (attachment)
  ;; => (:upload (:token "3.8b652b8c79f357694a04bd793f533c96"))
  (let ((path (plist-get attachment :path)))
    (unless (file-exists-p path)
      (error "%s: file not exist" path))
    (elmine/upload-file path)))

(defun orgmine-upload-attachents (plist)
  (let ((attachments (plist-get plist :attachments))
	uploads)
    (mapc (lambda (attachment)
	    (let ((path (plist-get attachment :path)))
	      (unless path
		(error "path is not specified in attachment plist: %s"
		       attachment))
	      (unless (file-exists-p path)
		(error "%s: file not exist" path))))
	  attachments)
    (mapc (lambda (attachment)
	    (let ((res-plist (orgmine-upload-attachent attachment)))
	      (if res-plist
		  (let ((upload (plist-get res-plist :upload))
			(filename (plist-get attachment :filename))
			(description (plist-get attachment :description)))
		    (setq upload (plist-put upload :filename filename))
		    (if description
			(setq upload
			      (plist-put upload :description description)))
		    (add-to-list 'uploads upload)))))
	  attachments)
    (if uploads
	;; workaround for `json-enconde-list', which wrongly handles
	;; list of plist as alist.
	(add-to-list 'uploads nil t))
    uploads))

(defun orgmine-submit-issue-update (issue force &optional no-prompt)
  "Submit the issue update to Redmine."
  (orgmine-submit-entry-update issue :id :subject
			       'orgmine-get-issue
			       (lambda (plist)
				 (orgmine-submit-issue-relations plist)
				 (let ((uploads
					(orgmine-upload-attachents plist)))
				   (if uploads
				       (setq plist
					     (plist-merge plist
							  (list
							   :uploads uploads
							   :attachments nil)))))
				 (elmine/update-issue plist)
				 (orgmine-fetch-issue t))
			       force no-prompt))

(defun orgmine-submit-version-update (version force &optional no-prompt)
  "Submit the version update to Redmine."
  (orgmine-submit-entry-update version :fixed_version_id :name
			       'orgmine-get-version
			       (lambda (plist)
				 (elmine/update-version plist)
				 (orgmine-fetch-version t))
			       force no-prompt))

;;;;

(defun orgmine-project (&optional parent)
  (let ((projects (elmine/get-projects)))
    (mapcar (lambda (project)
	      (orgmine-idname project))
	    projects)))

(defvar orgmine-project-hist nil)

(defun orgmine-read-project (&optional prompt)
  (or prompt (setq prompt "Project# "))
  (let* ((project (nth 1 (orgmine-get-property nil 'project nil t)))
	 (collection (orgmine-project project)))
    (if project
	(setq prompt (format "%s(default %s): " prompt project)))
    (completing-read prompt collection nil t nil
		     'orgmine-project-hist project)))

(defvar orgmine-project-versions nil)

(defun orgmine-project-versions (project)
  (let ((versions (elmine/get-project-versions project)))
    (mapcar (lambda (version)
	      (orgmine-idname version))
	    versions)))

(defun orgmine-current-issue ()
  "Return the number that point is on as a string.
If no number is on the position and the position is under the issuen entry,
return the issue number of the current entry."
  (or (save-match-data
	;; XXX
	(let ((word (current-word)))
	  (if (and word (string-match "\\([0-9]+\\)" word))
	      (match-string 1 word))))
      (let* ((issue (orgmine-find-headline-ancestor orgmine-tag-issue t))
	     (beg (org-element-property :begin issue))
	     (id (orgmine-get-id beg)))
	id)))

;; XXX
(defun orgmine-current-version ()
  (save-match-data
    (let ((word (current-word)))
      (if (and word (string-match "\\([0-9]+\\)" word))
	  (match-string 1 word)))))

(defvar orgmine-issue-hist nil)

(defun orgmine-read-issue (&optional prompt)
  (or prompt (setq prompt "Issue# "))
  (let* ((default (orgmine-current-issue)))
    (if default
	(setq prompt (format "%s(default %s): " prompt default)))
    (completing-read prompt nil nil nil nil
		     'orgmine-version-hist default)))

(defvar orgmine-version-hist nil)

(defun orgmine-read-version (&optional prompt collection-from-server)
  (or prompt (setq prompt "Version# "))
  (let* ((default (orgmine-current-version)))
    (if default
	(setq prompt (format "%s(default %s): " prompt default)))
    (let* ((project (nth 1 (orgmine-get-property nil 'project nil t)))
	   (collection (if collection-from-server
			   (orgmine-project-versions project))))
      (completing-read prompt collection nil nil nil
		       'orgmine-version-hist default))))

(defvar orgmine-project-trackers nil)

(defun orgmine-project-trackers (project)
  (let ((trackers (elmine/get-project-trackers project)))
    (mapcar (lambda (tracker)
	      (orgmine-idname tracker))
	    trackers)))

(defvar orgmine-tracker-hist nil)

(defun orgmine-read-tracker (&optional prompt)
  (or prompt (setq prompt "Tracker# "))
  (let* ((project (nth 1 (orgmine-get-property nil 'project nil t)))
	 (collection (orgmine-project-trackers project)))
    (completing-read prompt collection nil t nil
		     'orgmine-tracker-hist)))

(defun orgmine-properties ()
  "Return a list of editable property names for the current entry."
  (let ((tags (save-excursion
		(org-back-to-heading)
		(org-get-tags))))
    (cond ((member orgmine-tag-project tags)
	   (list "om_parent"))
	  ((member orgmine-tag-tracker tags)
	   (list "om_fixed_version"))
	  ((member orgmine-tag-version tags)
	   (list "om_status"))
	  (t ;; issue entry
	   (let ((names
		  (list "om_tracker" "om_parent" "om_done_ratio"
			"om_assigned_to" "om_fixed_version"
			"om_relation_relates"
			"om_relation_duplicates" "om_relation_duplicated"
			"om_relation_blocks" "om_relation_blocked"
			"om_relation_precedes" "om_relation_follows"
			"om_relation_copied_to" "om_relation_copied_from")))
	     (if (boundp 'orgmine-custom-fields)
		 (nconc names (mapcar 'car orgmine-custom-fields))
	       names))))))

(defvar orgmine-property-name-hist nil)

;; TODO: change keys per entry: issue, tracker, project, version
(defun orgmine-read-property-name ()
  "Read a property name."
  (let* ((completion-ignore-case t)
	 (keys (orgmine-properties))
	 (default-prop (or (car orgmine-property-name-hist)
			   "om_assigned_to"))
	 (property (completing-read
		    (concat "Property"
			    (if default-prop (concat " [" default-prop "]") "")
			    ": ")
		    (mapcar 'list keys)
		    nil nil nil 'orgmine-property-name-hist
		    default-prop)))
    (if (member property keys)
	property
      (or (cdr (assoc-string property keys t))
	  property))))

;;;;

(defun orgmine-update-issue (issue redmine-issue &optional force)
  "Update the entry of ISSUE (org-element data) per REDMINE-ISSUE.
If the issue of Redmine is not updated since last sync and FORCE is nil,
the entry is not updated."
  (orgmine-update-entry
   'issue issue redmine-issue force
   '(id tracker created_on updated_on closed_on
	parent status fixed_version ;; author
	start_date due_date done_ratio
	estimated_hours assigned_to project custom_fields relations)
   (lambda (plist beg end)
     (let ((description (plist-get plist :description))
	   (journals (plist-get plist :journals))
	   (attachments (plist-get plist :attachments)))
       ;; update journals
       (if journals (orgmine-insert-journals journals beg end))
       ;; update attachments
       (if attachments (orgmine-insert-attachments attachments beg end))
       ;; update entry description
       (if description (orgmine-insert-description description beg end))))))

(defun orgmine-update-version (version redmine-version &optional force)
  "Update the entry of VERSION (org-element data) per REDMINE-VERSION.
If the version of Redmine is not updated since last sync and FORCE is nil,
the entry is not updated."
  (orgmine-update-entry
   'fixed_version version redmine-version force
   '(fixed_version created_on updated_on closed_on status due_date project)))

(defun orgmine-update-tracker (tracker redmine-tracker &optional force)
  "Update the entry of TRACKER (org-element data) per REDMINE-TRACKER.
If the version of Redmine is not updated since last sync and FORCE is nil,
the entry is not updated."
  (orgmine-update-entry
   'tracker tracker redmine-tracker force '(trackers)))

(defun orgmine-update-project (project redmine-project &optional force)
  "Update the entry of PROJECT (org-element data) per REDMINE-PROJECT.
If the version of Redmine is not updated since last sync and FORCE is nil,
the entry is not updated."
  (orgmine-update-entry
   'project project redmine-project force
   '(project created_on updated_on status parent identifier)
   (lambda (plist beg end)
     (let ((description (plist-get plist :description)))
       ;; update entry description
       (if description (orgmine-insert-description description beg end))))))

(defun orgmine-copy-buffer-local-variables (buf-from buf-to)
  "Copy buffer local variables in BUF-FROM to BUF-TO.
The variables to be copies are whose names start with
\"orgmine-\", \"org-\", or \"elmine/\"."
  (with-current-buffer buf-to
    (mapc (lambda (var)
	    (let ((symbol (car var))
		  (value (cdr var)))
	      (if (string-match "^\\(orgmine-\\|org-\\|elmine/\\)"
				(symbol-name symbol))
		  (set (make-local-variable symbol) value))))
	  (buffer-local-variables buf-from))))

(defvar orgmine-id-list-alist nil)

(defun orgmine-id-list-cache (afile tag)
  (let* ((key (format "%s:%s" afile tag))
	 (value (cdr (assoc key orgmine-id-list-alist))))
    value))

(defun orgmine-id-list-cache-set (afile tag id-list)
  (let* ((key (format "%s:%s" afile tag))
	 (list (assoc key orgmine-id-list-alist))
	 (modification-time (nth 5 (file-attributes afile)))
	 (new-value (cons modification-time id-list)))
    (if list
	(setcdr list new-value)
      (add-to-list 'orgmine-id-list-alist (cons key new-value)))))

(defun orgmine-get-id-list (tag id-prop)
  (org-with-wide-buffer
   (goto-char (point-min))
   (let (id-list)
     (message "scanning %s IDs..." tag)
     (while (orgmine-find-headline tag)
       (let ((id (orgmine-get-id nil id-prop)))
	 (if id (add-to-list 'id-list (string-to-number id))))
       (outline-next-heading))
     (message "scanning %s IDs... done" tag)
     id-list)))

(defun orgmine-archived-ids (tag id-prop)
  (let ((afile (org-extract-archive-file)))
    (if (file-exists-p afile)
	(let* ((curbuf (current-buffer))
	       (visiting (find-buffer-visiting afile))
	       (buffer
		(or visiting
		    (prog2
			(message "opening archive file %s..." afile)
			(find-file-noselect afile)
		      (message "opening archive file %s... done" afile)))))
	  (unless buffer
	    (error "Cannot access file \"%s\"" afile))
	  (unless (eq buffer curbuf)
	    (with-current-buffer buffer
	      (let ((id-list-cache (orgmine-id-list-cache afile tag)))
		(if (and (not (buffer-modified-p))
			 (equal (nth 5 (file-attributes afile))
				(car id-list-cache)))
		    ;; use the cached id list if the archive file is
		    ;; not updated since the last scan and the buffer
		    ;; is not modified.
		    (cdr id-list-cache)
		  ;; Otherwise, scan the buffer for IDs and push the
		  ;; ID list to the cache.
		  (unless (eq major-mode 'org-mode) (org-mode))
		  (orgmine-mode)
		  (orgmine-copy-buffer-local-variables curbuf buffer)
		  (let ((id-list (orgmine-get-id-list tag id-prop)))
		    (orgmine-id-list-cache-set afile tag id-list)
		    id-list)))))))))

(defun orgmine-buffer-list ()
  "Returns the list of orgmine buffers"
  (let (buffers)
    (mapc (lambda (buf)
	    (with-current-buffer buf
	      (if orgmine-mode
		  (add-to-list 'buffers buf))))
	  (org-buffer-list 'agenda t))
    buffers))

(defun orgmine-archived-issues ()
  (orgmine-archived-ids orgmine-tag-issue 'id))

(defun orgmine-archived-versions ()
  (orgmine-archived-ids orgmine-tag-version 'fixed_version))


;;; Interactive Functions

(defun orgmine-fetch-issue (force)
  "Fetch redmine issue in the current position."
  (interactive "P")
  (let* ((issue (orgmine-find-headline-ancestor orgmine-tag-issue))
	 (beg (org-element-property :begin issue))
	 (id (orgmine-get-id beg)))
    (unless id (error "Redmine issue headline without ID (om_id prop)"))
    (let ((redmine-issue (elmine/get-issue-with-journals id)))
      (unless redmine-issue
	(error "issue #%s not found" id))
      (orgmine-update-issue issue redmine-issue force))
    (goto-char beg)))

(defun orgmine-fetch-version (force)
  "Fetch redmine version in the current position."
  (interactive "P")
  (let* ((version (orgmine-find-headline-ancestor orgmine-tag-version))
	 (beg (org-element-property :begin version))
;; 	 (id (orgmine-get-id 'version beg)))
	 (plist (orgmine-get-properties beg '(fixed_version)))
	 (version-id (plist-get plist :fixed_version_id)))
    (unless version-id
      (error "Redmine version headline without ID (om_version)."))
    (let ((redmine-version (elmine/get-version version-id)))
      (unless redmine-version
	(error "version #%s not found" version-id))
      (orgmine-update-version version redmine-version force))
    (goto-char beg)))

(defun orgmine-fetch-tracker (force)
  "Fetch redmine tracker in the current position."
  (interactive "P")
  (let* ((tracker (orgmine-find-headline-ancestor orgmine-tag-tracker))
	 (beg (org-element-property :begin tracker))
	 (plist (orgmine-get-properties beg '(tracker)))
	 (tracker-id (plist-get plist :tracker_id)))
    (unless tracker-id
      (error "Redmine tracker headline without ID (om_tracker)."))
    (let* ((redmine-trackers (elmine/get-trackers))
	   (redmine-tracker
	    (orgmine-plist-list-get redmine-trackers
				    :id (string-to-number tracker-id))))
      (unless redmine-tracker
	(error "tracker #%s not found" tracker-id))
      ;; tracker does not have :updated_on prop.  Update the headline
      ;; only when FORCE is non-nil
      (if force
	  (orgmine-update-tracker tracker redmine-tracker force)))
    (goto-char beg)))

(defun orgmine-fetch-project (force)
  "Fetch redmine project in the current position."
  (interactive "P")
  (let* ((project (orgmine-find-headline-ancestor orgmine-tag-project))
	 (beg (org-element-property :begin project))
	 (plist (orgmine-get-properties beg '(project)))
	 (project-id (plist-get plist :project_id)))
    (unless project-id
      (error "Redmine project headline without ID (om_project)."))
    (let ((redmine-project (elmine/get-project project-id)))
      (unless redmine-project
	(error "project #%s not found" project-id))
      (orgmine-update-project project redmine-project force))
    (goto-char beg)))

(defun orgmine-fetch-versions (force)
  (interactive "P")
  (let* ((subtree (orgmine-subtree-region))
	 (beg (car subtree)))
    (outline-next-heading)
    (orgmine-insert-all-versions force)
    (goto-char beg)
    (orgmine-sync-subtree-recursively (list orgmine-tag-version))
    (goto-char beg)))

(defun orgmine-fetch (force)
  "Fetch redmine issue, version, tracker, or project in the current position."
  (interactive "P")
  (let ((pos (point)))
    (save-excursion
      (unless (outline-on-heading-p t)
	(outline-previous-heading))
      (setq pos
	    (let ((tags (org-get-tags)))
	      (cond ((member orgmine-tag-version tags)
		     (orgmine-fetch-version force))
		    ((member orgmine-tag-versions tags)
		     (orgmine-fetch-versions force))
		    ((member orgmine-tag-tracker tags)
		     (orgmine-fetch-tracker force))
		    ((member orgmine-tag-project tags)
		     (prog1
			 (orgmine-fetch-project force)
		       (orgmine-fetch-versions force)))
		    (t
		     (orgmine-fetch-issue force)))
	      (point))))
    (goto-char pos)))

(defun orgmine-insert-issue (id &optional arg cache demote)
  "Insert redmine issue in the current position."
  (interactive (list (read-string "Issue# to insert: ") current-prefix-arg))
  (if (numberp id) (setq id (number-to-string id)))
;;   (let ((redmine-issue (elmine/get-issue-with-journals id)))
  (let ((redmine-issue (orgmine-get-issue id cache)))
    ;; TODO: catch error from `elmine/get-issue`.
    (unless redmine-issue
      (error "Issue #%s not exist on Redmine or some error occurred." id))
    (if demote
	(orgmine-insert-demoted-heading)
      (org-insert-heading arg))
    (org-toggle-tag orgmine-tag-issue 'on)
    (org-set-property "om_id" id)
    (let ((issue (org-element-at-point)))
      (orgmine-update-issue issue redmine-issue))))

(defun orgmine-add-issue (arg)
  "Add redmine issue entry at the current position.
NB: the issue is not submitted to the server."
  (interactive "P")
  (org-insert-heading arg)
  (orgmine-todo (orgmine-default-todo-keyword))
  (let ((pos (point)))
    (org-toggle-tag orgmine-tag-issue 'on)
    (org-toggle-tag orgmine-tag-create-me 'on)
    (insert " ")
    (goto-char pos)
    (org-set-property "om_start_date"
		      (format-time-string (org-time-stamp-format nil t)
					  (current-time)))))

(defun orgmine-find-new-journal (end)
  (org-goto-first-child)
  (catch 'found
    (while (orgmine-find-headline orgmine-tag-update-me end t)
      (if (member orgmine-tag-journal (org-get-tags))
	  (throw 'found (point)))
      (outline-next-heading))
    nil))

(defun orgmine-add-journal (arg)
  "Add redmine journal entry for the issue at the current position.
NB: the journal is not submitted to the server."
  (interactive "P")
  (let* ((issue (orgmine-find-headline-ancestor orgmine-tag-issue))
	 (beg (org-element-property :begin issue))
	 (end (copy-marker (save-excursion
			     (goto-char beg)
			     (cdr (orgmine-subtree-region)))))
	 (id (orgmine-get-id beg))
	 (journal (list :id nil :created_on nil :user nil :notes "\n")))
    (goto-char beg)
    (show-branches)
    (if arg
	(orgmine-find-journals end nil t)
      (orgmine-find-journals end t t)
      (if (orgmine-find-new-journal end)
	  (progn
	    (if (re-search-forward org-block-regexp end t)
		(org-previous-block 1)
	      (if (fboundp 'org-end-of-meta-data-and-drawers)
		  (org-end-of-meta-data-and-drawers)
		(org-end-of-meta-data t))
	      (forward-line -1)
	      (orgmine-insert-note "\n" t))
	    (message "new journal entry already exist."))
	(let ((orgmine-journal-title-format "New Journal"))
	  (orgmine-insert-journal (point) end journal id 0 t))
	(org-toggle-tag orgmine-tag-update-me 'on)
	(outline-next-heading)
	(forward-line -2)
	(move-end-of-line nil))
      (set-marker end nil))))

(defun orgmine-find-description (end)
  (org-goto-first-child)
  (if (orgmine-find-headline orgmine-tag-description end t)
      (point)))

(defun orgmine-add-description (arg)
  "Add redmine description entry for the issue at the current position.
NB: the description is not submitted to the server."
  (interactive "P")
  (let* ((pos (point))
	 (region (and (orgmine-current-issue-heading)
		      (orgmine-subtree-region)))
	 (beg (car region))
	 (end (copy-marker (cdr region))))
    (show-branches)
    (if arg
	(unless (orgmine-find-description end)
	  (goto-char pos)
	  (message "no description entry found."))
      (if (orgmine-find-description end)
	  (progn
	    (if (not (member orgmine-tag-update-me (org-get-tags)))
		(org-toggle-tag orgmine-tag-update-me 'on))
	    (if (re-search-forward org-block-regexp
				   (cdr (orgmine-subtree-region)) t)
		(org-previous-block 1)
	      (if (fboundp 'org-end-of-meta-data-and-drawers)
		  (org-end-of-meta-data-and-drawers)
		(org-end-of-meta-data t))
	      (if (bolp)
		  (forward-line -1)
		(move-beginning-of-line nil))
	      (orgmine-insert-note "" t))
	    (message "description entry already exist."))
	(orgmine-insert-description "" beg end t)
        (unless (member orgmine-tag-update-me (org-get-tags))
          (org-toggle-tag orgmine-tag-update-me 'on))))
    (set-marker end nil)))

(defun orgmine-find-attachments (end)
  (org-goto-first-child)
  (if (orgmine-find-headline orgmine-tag-attachments end t)
      (point)))

(defun orgmine-add-attachment (arg)
  "Add redmine attachments entry for the issue at the current position.
NB: the attachments is not submitted to the server."
  (interactive "P")
  (let* ((pos (point))
	 (region (and (orgmine-current-issue-heading)
		      (orgmine-subtree-region)))
	 (beg (car region))
	 (end (copy-marker (cdr region))))
    (show-branches)
    (if arg
	(unless (orgmine-find-attachments end)
	  (goto-char pos)
	  (message "no attachments entry found."))
      (if (orgmine-find-attachments end)
	  (message "attachments entry already exist.")
	(orgmine-insert-attachments nil beg end t)
	(forward-line -1))
      (show-entry)
      (org-toggle-tag orgmine-tag-update-me 'on)
      (outline-next-heading)
      (open-line 1)
      (insert "x") ;; dummy char to indent properly
      (org-indent-line)
      (delete-backward-char 1)
      (insert "- ")
      (message "Please insert a \"file:\" link here to be attached."))
    (set-marker end nil)))

(defun orgmine-insert-version (fixed-version &optional arg cache)
  "Insert Redmine version entry in the current position."
  (interactive (list (orgmine-read-version "Version# to insert: " t)
		     current-prefix-arg))
  (if (numberp fixed-version)
      (setq fixed-version (number-to-string fixed-version)))
  (let ((redmine-version (orgmine-get-version fixed-version cache)))
    (unless redmine-version
      (error "Version #%s does not exist on Redmine or some error occurred."
	     fixed-version))
;;     (org-insert-heading arg)
;;     (org-toggle-tag orgmine-tag-version 'on)
    (show-branches)
    (move-beginning-of-line nil)
    (orgmine-insert-demoted-heading "" (list orgmine-tag-version))
    (org-set-property "om_fixed_version" fixed-version)
    (let ((version (org-element-at-point)))
      (orgmine-update-version version redmine-version))))

(defun orgmine-insert-all-versions (force)
  "Insert all of the Redmine version entries in the current position.
The following version entries are not inserted:
 - a version entry already exists in the buffer, or
 - a version entry that was archived to the archive file."
  (interactive "P")
  (let* ((project (nth 1 (orgmine-get-property nil 'project nil t)))
	 (redmine-versions (elmine/get-project-versions project))
	 (archived-versions (orgmine-archived-versions))
	 (count 0))
    (mapc (lambda (redmine-version)
	    (let ((fixed-version (plist-get redmine-version :id)))
	      (if (or force
		      (and (not (member fixed-version archived-versions))
			   (not (save-excursion
				  (goto-char (point-min))
				  (orgmine-find-version fixed-version
							(point-max))))))
		  (progn
		    (orgmine-insert-version fixed-version redmine-versions)
		    (setq count (1+ count))))))
	  redmine-versions)
    (if (> count 0)
	(message "%d versions inserted" count)
      (message "no version inserted"))))

(defun orgmine-insert-tracker (tracker &optional arg cache)
  "Insert Redmine tracker entry in the current position."
  (interactive (list (orgmine-read-tracker) current-prefix-arg))
  (if (numberp tracker)
      (setq tracker (number-to-string tracker)))
  (let ((redmine-tracker (orgmine-get-tracker tracker cache)))
    (unless redmine-tracker
      (error "Tracker #%s does not exist on Redmine or some error occurred."
	     tracker))
    (org-insert-heading arg)
    (org-toggle-tag orgmine-tag-tracker 'on)
    (org-set-property "om_tracker" tracker)
    (let ((tracker (org-element-at-point)))
      (orgmine-update-tracker tracker redmine-tracker))))

(defun orgmine-insert-project (project &optional arg cache)
  "Insert Redmine project entry in the current position."
  (interactive (list (orgmine-read-project) current-prefix-arg))
  (let ((redmine-project (orgmine-get-project project cache)))
    (unless redmine-project
      (error "Project #%s does not exist on Redmine or some error occurred."
	     project))
;;     (org-insert-heading arg)
    (outline-insert-heading)
    (org-toggle-tag orgmine-tag-project 'on)
    (org-set-property "om_project" project)
    (let ((project (org-element-at-point)))
      (orgmine-update-project project redmine-project))))

(defun orgmine-add-version (arg)
  "Add new redmine version entry at the current position.
NB: the version is not submitted to the server."
  (interactive "P")
  (org-insert-heading arg)
  (let ((pos (point)))
    (org-toggle-tag orgmine-tag-version 'on)
    (org-toggle-tag orgmine-tag-create-me 'on)
    (insert " ")))

(defun orgmine-add-project (name project-id parent &optional arg)
  "Add new redmine project entry at the current position.
NB: the project is not submitted to the server."
  (interactive (list (read-string "Project name to create: ")
		     (read-string "Project identifier to create: ")
		     (read-string "Parent project: ")
		     current-prefix-arg))
  (org-insert-heading arg)
  (let ((pos (point)))
    (org-toggle-tag orgmine-tag-project 'on)
    (org-toggle-tag orgmine-tag-create-me 'on)
    (let ((plist (list :project_id project-id)))
      (if (and parent (> (length parent) 0))
	  (setq plist (plist-put plist :parent parent)))
      (orgmine-set-properties 'project plist '(project_id parent)))
    (insert " " (or name ""))
    (goto-char (point))))

(defun orgmine-set-entry-property (property value &optional arg)
  "In the current entry of issue, project, tracker, or version,
set PROPERTY to VALUE."
  (interactive (list (progn
		       (orgmine-current-entry-heading)
		       (orgmine-read-property-name))
		     nil current-prefix-arg))
  (orgmine-current-entry-heading)
  (if arg
;;       (org-delete-property property)
      (org-entry-delete nil property)
    (org-set-property property value))
  (unless (member orgmine-tag-create-me (org-get-tags))
    (org-toggle-tag orgmine-tag-update-me 'on)))

(defun orgmine-set-assigned-to (value &optional arg)
  "In the current issue, set :assigned_to property to VALUE."
  (interactive (list nil current-prefix-arg))
  (orgmine-set-entry-property (orgmine-property-name 'assigned_to) value arg))

(defun orgmine-set-done-ratio (value &optional arg)
  "In the current issue, set :done_ratio property to VALUE."
  (interactive (list nil current-prefix-arg))
  (orgmine-set-entry-property (orgmine-property-name 'done_ratio) value arg))

(defun orgmine-set-tracker (value &optional arg)
  "In the current issue, set :tracker property to VALUE."
  (interactive (list nil current-prefix-arg))
  (orgmine-set-entry-property (orgmine-property-name 'tracker) value arg))

(defun orgmine-set-version (value &optional arg)
  "In the current issue, set :fixed_version property to VALUE."
  (interactive (list nil current-prefix-arg))
  (orgmine-set-entry-property (orgmine-property-name 'fixed_version) value arg))

;; TODO
(defun orgmine-set-custom-field (value &optional arg)
  "In the current issue, set :om_cf_* property to VALUE."
  (interactive (list nil current-prefix-arg))
  (orgmine-set-entry-property nil value arg))

(defun orgmine-create-issue (issue)
  "Submit new issue entry to Redmine."
  (save-excursion
    (unless (member orgmine-tag-create-me (org-get-tags))
      (error "No redmine issue headline to create found"))
    (let* ((plist (orgmine-collect-update-plist issue :subject))
	   (subject (plist-get plist :subject))
	   (id (plist-get plist :id)))
      (if (or (null subject) (equal subject ""))
	  (error "Subject is not specified."))
      (if id
	  (error "Issue ID (%s) is specified for new issue." id))
;;       (if (y-or-n-p (format "Will you submit new issue? %s" plist))
      (if (orgmine-y-or-n-p (format "Will you submit new issue %s ?" subject)
			    plist)
	  (let* ((uploads
		  (orgmine-upload-attachents plist)))
	    (if uploads
		(setq plist
		      (plist-merge plist :uploads uploads :attachments nil)))
	    (let* ((res-plist (elmine/create-issue plist))
		   (redmine-issue (plist-get res-plist :issue))
		   (id (plist-get redmine-issue :id)))
	      (if id
		  (progn
		    (orgmine-set-properties 'issue redmine-issue '(id))
		    (org-toggle-tag orgmine-tag-create-me 'off)
		    (orgmine-fetch-issue t))
		(error "No issue created: %s" res-plist))))))))

(defun orgmine-create-version (version)
  "Submit new version entry to Redmine."
  (save-excursion
    (unless (member orgmine-tag-create-me (org-get-tags))
      (error "No redmine version headline to create found"))
    (let* ((plist (orgmine-collect-update-plist version :name))
	   (subject (plist-get plist :name))
	   (id (plist-get plist :fixed_version_id)))
;;       (plist-put plist :name subject)
      (if (or (null subject) (equal subject ""))
	  (error "Version name is not specified."))
      (if id
	  (error "Version ID (%s) is specified for new version." id))
      (if (orgmine-y-or-n-p (format "Will you submit new version %s ?" subject)
			    plist)
	  (let* ((res-plist (elmine/create-version plist))
		 (redmine-version (plist-get res-plist :version))
		 (id (plist-get redmine-version :id))
		 (errors (plist-get res-plist :errors)))
	    (if id
		(progn
		  (orgmine-set-properties 'fixed_version
					  redmine-version '(fixed_version))
		  (org-toggle-tag orgmine-tag-create-me 'off)
		  (orgmine-fetch-version nil))
	      (error (format "No version created: %s"
			     (mapconcat 'identity errors " / ")))))))))

(defun orgmine-submit-issue (force)
  "Submit new issue entry or submit issue update to Redmine."
  (interactive "P")
  (let ((issue (orgmine-find-headline-ancestor orgmine-tag-issue)))
    (goto-char (org-element-property :begin issue))
    (save-excursion
;;       (goto-char (org-element-property :begin issue))
      (if (member orgmine-tag-create-me (org-get-tags))
	  (orgmine-create-issue issue)
	(orgmine-submit-issue-update issue force)))))

(defun orgmine-submit-version (force)
  "Submit new version entry or submit version update to Redmine."
  (interactive "P")
  (let ((version (orgmine-find-headline-ancestor orgmine-tag-version)))
    (goto-char (org-element-property :begin version))
    (save-excursion
;;       (goto-char (org-element-property :begin version))
      (if (member orgmine-tag-create-me (org-get-tags))
	  (orgmine-create-version version)
	(orgmine-submit-version-update version force)))))

(defun orgmine-submit (force)
  "Submit new entry or update to Redmine.
The entry could be issue or version in the current position.
Submitting update of project and tracker is not supported."
  (interactive "P")
  (let ((pos (point)))
    (save-excursion
      (unless (outline-on-heading-p t)
	(outline-previous-heading))
      (setq pos
	    (let ((tags (org-get-tags)))
	      (cond ((member orgmine-tag-version tags)
		     (orgmine-submit-version force))
;; 		    ((member orgmine-tag-tracker tags)
;; 		     (orgmine-submit-tracker force))
;; 		    ((member orgmine-tag-project tags)
;; 		     (orgmine-submit-project force))
		    ((member orgmine-tag-tracker tags))
		    ((member orgmine-tag-project tags))
		    ((member orgmine-tag-versions tags))
		    (t
		     (orgmine-submit-issue force)))
	      (point))))
    (goto-char pos)))

(defun orgmine-submit-issue-region (beg end &optional force)
  "Submit new issue entries or submit issue updates to Redmine
found in the region from BEG to END."
  (interactive "r\nP")
  (let ((pos (point)))
    (goto-char beg)
    (while (orgmine-find-headline orgmine-tag-issue end)
      (orgmine-submit-issue force)
      (outline-next-heading))
    (goto-char pos)))

;;;

(defvar orgmine-ignore-ids)

(defun orgmine-find-issue (redmine-id end)
  (if (numberp redmine-id)
      (setq redmine-id (number-to-string redmine-id)))
  (orgmine-find-headline-prop orgmine-tag-issue 'id redmine-id end))

(defun orgmine-goto-issue (id arg)
  "Goto issue entry of ID."
;;   (interactive (list (read-string "Issue# ") current-prefix-arg))
  (interactive (list (orgmine-read-issue "Issue# ") current-prefix-arg))
  (when arg
    (orgmine-show-issues nil)
    (org-remove-occur-highlights))
  (let ((pos (point)))
    (goto-char (point-min))
    (if (orgmine-find-issue id (point-max))
	(set-mark pos)
      (goto-char pos)
      (error "Issue#%s not found" id))))

(defun orgmine-goto-parent-issue (arg)
  "Goto parent issue entry of ID."
  (interactive "P")
  (let* ((issue (orgmine-find-headline-ancestor orgmine-tag-issue))
	 (beg (org-element-property :begin issue))
	 (id (orgmine-get-id beg))
	 (parent (nth 1 (orgmine-get-property beg 'parent))))
    (unless parent (error "No parent issue for issue #%s" id))
    (orgmine-goto-issue parent arg)))

(defun orgmine-find-version (redmine-id end)
  (if (numberp redmine-id)
      (setq redmine-id (number-to-string redmine-id)))
  (orgmine-find-headline-prop orgmine-tag-version 'fixed_version
			      redmine-id end))

(defun orgmine-goto-version (id arg)
  (interactive (list (orgmine-read-version "Version# " nil) current-prefix-arg))
;;   (interactive (list (read-string "Version# ") current-prefix-arg))
  (when arg
    (orgmine-show-versions nil)
    (org-remove-occur-highlights))
  (let ((pos (point)))
    (goto-char (point-min))
    (if (orgmine-find-version id (point-max))
	(set-mark pos)
      (goto-char pos)
      (error "Version#%s not found" id))))

;;;;

(defun orgmine-refile (&optional goto default-buffer)
  "Move the current issue entry to another heading."
  (interactive "P")
  (let* ((issue (orgmine-find-headline-ancestor orgmine-tag-issue t))
	 (beg (org-element-property :begin issue)))
    (if (and (not issue) (not goto))
	(error "Not in an issue entry to refile."))
    (goto-char (or beg (point)))
    (let ((org-refile-targets `((nil :maxlevel . 1)
				(nil :tag . ,orgmine-tag-project)
				(nil :tag . ,orgmine-tag-version)
				(nil :tag . ,orgmine-tag-tracker))))
      (org-refile goto default-buffer)
      (save-excursion
	(org-refile-goto-last-stored)
	(mapc (lambda (property)
		(org-entry-delete nil property))
	      '("om_project" "om_fixed_version" "om_tracker"))
	(org-toggle-tag orgmine-tag-update-me 'on)))))

;;;;

(defun orgmine-match-sparse-tree (todo-only match what)
  "Creating a sparse tree according to tags string MATCH with message."
  (interactive "P")
  (message "highlighting %s..." what)
  (org-match-sparse-tree todo-only match)
  (message "highlighting %s... done" what))

(defun orgmine-show-issues (todo-only)
  "Show entries of Redmine issue."
  (interactive "P")
  (orgmine-match-sparse-tree todo-only orgmine-tag-issue "issues"))

(defun orgmine-show-child-issues (todo-only)
  "Show current entry and entries of Redmine child issues of the current issue."
  (interactive "P")
  (let* ((issue (orgmine-find-headline-ancestor orgmine-tag-issue))
	 (beg (org-element-property :begin issue))
	 (id (orgmine-get-id beg)))
    (unless id (error "Redmine issue headline without ID (om_id prop)"))
    (org-with-wide-buffer
     (goto-char (point-min))
     (unless (orgmine-find-headline-prop orgmine-tag-issue 'parent id)
       (error "No child issue found for issue #%s" id)))
    (let ((match (format "%s+om_parent=%s|om_id=%s" orgmine-tag-issue id id))
	  (what (format "#%s and its child issues..." id)))
      (orgmine-match-sparse-tree todo-only match what)
;;       (goto-char beg)
;;       (org-reveal)
      )))

(defun orgmine-show-versions (arg)
  "Show Version entries."
  (interactive "P")
  (orgmine-match-sparse-tree nil orgmine-tag-version "versions"))

(defun orgmine-show-trackers (arg)
  "Show Tracker entries."
  (interactive "P")
  (orgmine-match-sparse-tree nil orgmine-tag-tracker "trackers"))

(defun orgmine-show-projects (arg)
  "Show Project entries."
  (interactive "P")
  (orgmine-match-sparse-tree nil orgmine-tag-project "projects"))

(defun orgmine-show-all (arg)
  "Show Issues, Versions, Trackers, and Projects entries."
  (interactive "P")
  (let ((match (concat orgmine-tag-issue "|" orgmine-tag-version "|"
		       orgmine-tag-tracker "|" orgmine-tag-project)))
    (orgmine-match-sparse-tree nil match
			       "issues, versions, trackers, and projects")))

(defun orgmine-show-descriptions (arg)
  "Show Description entries."
  (interactive "P")
  (orgmine-match-sparse-tree nil orgmine-tag-description
			     "description headlines"))

(defun orgmine-show-journals (arg)
  "Show Journal entries."
  (interactive "P")
  (orgmine-match-sparse-tree nil orgmine-tag-journal "journal headlines"))

(defun orgmine-show-attachments (arg)
  "Show Attachments entries."
  (interactive "P")
  (orgmine-match-sparse-tree nil orgmine-tag-attachments
			     "attachment headlines"))

(defun orgmine-show-create (arg)
  "Show entries to create."
  (interactive "P")
  (orgmine-match-sparse-tree nil orgmine-tag-create-me "entries to create"))

(defun orgmine-show-update (arg)
  "Show entries to update."
  (interactive "P")
  (orgmine-match-sparse-tree nil orgmine-tag-update-me "entries to update"))

(defun orgmine-show-create-or-update (arg)
  "Show entries to create-or-update."
  (interactive "P")
  (orgmine-match-sparse-tree nil (format "%s|%s" orgmine-tag-create-me
					 orgmine-tag-update-me)
			     "entries to create or to update"))

(defun orgmine-show-assigned-to (who todo-only)
  "Show entries assigned to WHO."
  (interactive (list (org-icompleting-read
		      "Assigned To: "
		      (mapcar #'list (org-property-values "om_assigned_to")))
		     current-prefix-arg))
  (let ((match (format "%s+om_assigned_to=\"%s\"" orgmine-tag-issue who))
	(what (format "issues assigned to %s..." who)))
    (orgmine-match-sparse-tree todo-only match what)))

(defun orgmine-show-assigned-to-me (todo-only)
  "Show entries of Redmine issue/version to update."
  (interactive "P")
  (let ((me (org-entry-get (point-min) "om_me" t)))
    (unless me
      (error
       "om_me property not found. define it by \"#+PROPERTY om_me\" line"))
    (orgmine-show-assigned-to me todo-only)))

(defun orgmine-show-notes (arg)
  "Show notes."
  (interactive "P")
  (org-occur (regexp-quote orgmine-note-block-begin)))

;;;;

(defun orgmine-get-filters (beg)
  "Return filters for the current subtree to get issues."
  (save-excursion
    (org-back-to-heading t)
    (let* ((plist
	    (orgmine-get-properties beg '(project fixed_version tracker) t t))
;; 	 (filters (plist-merge '(list :status_id "*" :subproject_id "!*"
;; 				      :tracker_id "!*" :fixed_version_id "*")
;; 			       plist)))
;; 	 (filters (plist-merge (list :status_id "*" :subproject_id "!*"
;; 				     :tracker_id "!*")
	   (filters (plist-merge (list :status_id "*" :subproject_id "!*")
				 plist)))
      (if (member orgmine-tag-issue (org-get-tags))
	  (let ((id (orgmine-get-id nil)))
	    ;; XXX: :parent_id does not work for filter???
	    (setq filters (plist-put filters :parent_id id))))
      filters)))

(defun orgmine-update-issue-maybe (id beg end)
  "Update issuen entry and return non-nil if it exists in the buffer.
Otherwise, return nil."
  (goto-char beg)
  (let* ((issue (and (orgmine-find-issue id end)
		     (org-element-at-point))))
    (if issue
	;; refetch issue so that it contains journals/attachments.
	(let ((redmine-issue (orgmine-get-issue id nil)))
	  (orgmine-update-issue issue redmine-issue force)
	  (add-to-list 'orgmine-ignore-ids id)
	  (point)))))

(defun orgmine-insert-or-update-issue (id-list end force)
  "Insert or update the issue entries of ID-LIST.
If the issue entry does not exist after the current position,
new entry will be inserted into the current position."
  (let ((beg (point)))
    (mapc (lambda (id)
	    (or (member id orgmine-ignore-ids)
		(orgmine-update-issue-maybe id beg end)
		(progn
		  ;; insert issue as new entry.
		  (goto-char beg)
		  (outline-next-heading)
		  (orgmine-insert-issue id nil nil t) ; XXX: refetch
		  (if (= (funcall outline-level) 1)
		      (org-demote-subtree)))))
	  id-list)))

(defun orgmine-get-issues (beg)
  "get issues from redmine on current condition."
  (goto-char beg)
  (if (orgmine-tags-in-tag-p (list orgmine-tag-project orgmine-tag-version
				   orgmine-tag-tracker)
			     (org-get-tags))
      (let* ((filters (orgmine-get-filters beg))
	     (project (plist-get filters :project_id))
	     ;; XXX: elmine/get-issues does not return issues with journals
	     ;; even when ':include "journals"' is passed as the parameter.
	     (redmine-issues
	      (if (not project)
		  (error "no project property (project_id) exists")
		(message "retrieving issues with filter: %s" filters)
		(apply 'elmine/get-project-issues project filters))))
	(prog1 redmine-issues
	  (if (not redmine-issues)
	      (message "no issue exists for %s" filters)
	    (message "%d issue(s) retrieved." (length redmine-issues)))))
;;     (message "not a region for sync issues")
    nil))

(defun orgmine-collect-issues (beg end redmine-issues
				   &optional force update-only)
  "collect issues id list between BEG and END which needs to be updated
or newly inserted per REDMINE-ISSUES."
  (let (id-list)
    (mapc (lambda (redmine-issue)
	    (goto-char beg)
	    (let* ((id (plist-get redmine-issue :id))
		   (issue (and (orgmine-find-issue id end)
			       (org-element-at-point)))
		   (issue-before-region-p (save-excursion
					    (goto-char (point-min))
					    (orgmine-find-issue id beg)))
		   (issue-after-region-p (save-excursion
					   (goto-char end)
					   (orgmine-find-issue id
							       (point-max)))))
	      (cond ((member id orgmine-ignore-ids)
		     (message "issue #%s skipped (updated or archived)" id))
		    ((and (not issue)
			  (or issue-before-region-p issue-after-region-p))
		     (message "issue #%s skipped (exists outside region)" id))
		    ((and (not force) issue
			  (orgmine-entry-up-to-date-p issue redmine-issue))
		     (message "issue #%s skipped (no change since last sync)"
			      id))
		    ((and update-only (not issue))
		     (message "issue #%s skipped (not inside region)" id))
		    (t (add-to-list 'id-list id)))))
	  (reverse redmine-issues))
    id-list))

(defun orgmine-sync-issues (beg end &optional force update-only cache)
  "update entries between BEG and END from the condition.
If UPDATE-ONLY is nil, insert issue that does not exist in the buffer."
  (goto-char beg)
  (let* ((redmine-issues (orgmine-get-issues beg))
	 (id-list (orgmine-collect-issues beg end redmine-issues
					  force update-only)))
    (cond ((and redmine-issues (null id-list))
	   (message "%d issue(s) retrieved - no issue to sync."
		    (length redmine-issues)))
	  (id-list
	   (goto-char beg)
	   (orgmine-insert-or-update-issue id-list end t)
	   (message "%d issue(s) retrieved - synchronized issues: %s"
		    (length redmine-issues)
		    (mapconcat (lambda (id) (format "#%s" id))
			       id-list " "))))))

(defun orgmine-sync-region (beg end &optional force update-only cache)
  (interactive "r\nP")
  (if (and (org-called-interactively-p 'interactive)
	   (not (org-region-active-p)))
      (error "region not active"))
  (let ((orgmine-ignore-ids orgmine-ignore-ids))
    (if (org-called-interactively-p 'interactive)
	(setq orgmine-ignore-ids (orgmine-archived-issues)))
    (setq end (copy-marker end))
    (org-with-wide-buffer			; XXX
     (orgmine-submit nil)
     (goto-char beg)
     (orgmine-submit-issue-region beg end nil)
     ;; update version/tracker/project properties
     (goto-char beg)
     (orgmine-fetch force) ; XXX: issue headline before beg could be updated.
     ;; update issues
     (goto-char beg)
     (orgmine-sync-issues beg end force update-only)
     (set-marker end nil))))

(defun orgmine-sync-subtree (force)
  (interactive "P")
  (org-with-wide-buffer
   (let* ((subtree (orgmine-subtree-region))
	  (beg (car subtree))
	  (end (cdr subtree))
	  (orgmine-ignore-ids (orgmine-archived-issues)))
     (narrow-to-region beg end)
     (orgmine-sync-region beg end force))))

(defun orgmine-sync-subtree-recursively (&optional tags force)
  "call `orgmine-sync-subtree' on headlines of specific TAGS recursively
in depth first manner."
  (interactive (list nil current-prefix-arg))
  (or tags (setq tags (list orgmine-tag-project orgmine-tag-version
			    orgmine-tag-tracker orgmine-tag-versions)))
  (let* ((region (orgmine-subtree-region))
	 (beg (car region))
	 (end (copy-marker (cdr region))))
    (show-branches)
    (save-excursion
      (if (org-goto-first-child)
	  (orgmine-map-region (lambda ()
				(orgmine-sync-subtree-recursively tags force))
			      (point) end t)))
    (if (orgmine-tags-in-tag-p tags (org-get-tags))
	(orgmine-sync-subtree force))
    (set-marker end nil)
;;     (goto-char end)))
    (goto-char beg)))

(defun orgmine-sync-buffer (&optional force)
  "Synchronize the whole entries in the buffer."
  (interactive "P")
  (when (y-or-n-p "Will you sync the whole buffer (it may take long time) ? ")
    (message ">>> starting buffer synchronization ------------------------")
    (org-with-wide-buffer
     (let ((orgmine-ignore-ids (orgmine-archived-issues))
	   (beg (progn
		  (goto-char (point-min))
		  (and (org-before-first-heading-p) (outline-next-heading))
		  (point)))
	   (end (copy-marker (point-max))))
       ;; sync each subtrees one by one from top to bottom of buffer.
       (goto-char beg)
       (let ((tags (list orgmine-tag-project orgmine-tag-version
			 orgmine-tag-tracker orgmine-tag-versions)))
	 (while (re-search-forward "^\\* " nil t)
	   (save-excursion
	     (orgmine-sync-subtree-recursively tags force))
	   (outline-next-heading)))
       ;;
       (goto-char beg)
       (orgmine-sync-issues beg end force t)
       (set-marker end nil)))
    (message ">>> ending buffer synchronization ------------------------")
    (message
     "check *Messages* buffer for entries that might not be sync'ed.")))

(defun orgmine-sync-all-buffers (&optional force)
  "Synchronize the whole entries in all of the orgmine buffers."
  (interactive "P")
  (save-window-excursion
    (let ((buffers (orgmine-buffer-list)))
      (mapc (lambda (buf)
	      (switch-to-buffer buf)
	      (orgmine-sync-buffer force))
	    buffers))))

(defun orgmine-ediff-entry (beg id-prop orgmine-fetch-entry-func
				&optional show-no-child)
  "Run Ediff on local entry and Redmine server entry."
  (interactive "P")
  (org-with-wide-buffer
   (goto-char beg)
   (let* ((subtree (orgmine-subtree-region))
	  (beg (car subtree))
	  (end (if show-no-child (progn (goto-char beg)
					(outline-next-heading)
					(point))
		 (cdr subtree)))
	  (contents (buffer-substring beg end))
	  (id (orgmine-get-id beg id-prop)))
     (unless id (error "Redmine issue headline without ID (om_id prop)"))
     (narrow-to-region beg end)
     (show-all)
     (goto-char (point-min))
     (let ((level (funcall outline-level))
	   (buf-a (get-buffer-create "*ORGMINE-LATEST*"))
	   (buf-b (current-buffer)))
       (with-current-buffer buf-a
	 (read-only-mode 0)
	 (erase-buffer)
	 (org-mode)
	 (orgmine-mode)
	 (orgmine-copy-buffer-local-variables buf-b buf-a)
	 (goto-char (point-min))
	 (insert contents)
	 (goto-char (point-min))
	 (funcall orgmine-fetch-entry-func t)
;; 	 (goto-char (point-max))
;; 	 (unless (bolp) (insert "\n"))
	 (goto-char (point-min))
	 (show-all)
	 (set-buffer-modified-p nil)
	 (read-only-mode))
       (defvar orgmine-ediff-buf-a)
       (setq orgmine-ediff-buf-a buf-a)
       (ediff-buffers buf-a buf-b
		      '((lambda ()
			  (make-local-variable 'ediff-quit-hook)
			  (add-hook 'ediff-quit-hook
				    (lambda ()
				      (kill-buffer orgmine-ediff-buf-a))))))
       ))))

(defun orgmine-ediff-issue (arg)
  "Run Ediff on local issue entry and Redmine server issue entry."
  (interactive "P")
  (let ((issue (orgmine-find-headline-ancestor orgmine-tag-issue)))
    (orgmine-ediff-entry (org-element-property :begin issue)
;; 			 'id 'orgmine-insert-issue nil)))
			 'id 'orgmine-fetch-issue nil)))

(defun orgmine-ediff-version (arg)
  "Run Ediff on local version entry and Redmine server version entry."
  (interactive "P")
  (let ((version (orgmine-find-headline-ancestor orgmine-tag-version)))
    (orgmine-ediff-entry (org-element-property :begin version)
;; 			 'fixed_version 'orgmine-insert-version t)))
			 'fixed_version 'orgmine-fetch-version t)))

(defun orgmine-ediff-tracker (arg)
  "Run Ediff on local tracker entry and Redmine server tracker entry."
  (interactive "P")
  (let ((tracker (orgmine-find-headline-ancestor orgmine-tag-tracker)))
    (orgmine-ediff-entry (org-element-property :begin tracker)
;; 			 'tracker 'orgmine-insert-tracker t)))
			 'tracker 'orgmine-fetch-tracker t)))

(defun orgmine-ediff-project (arg)
  "Run Ediff on local project entry and Redmine server project entry."
  (interactive "P")
  (let ((project (orgmine-find-headline-ancestor orgmine-tag-project)))
    (orgmine-ediff-entry (org-element-property :begin project)
;; 			 'project 'orgmine-insert-project nil)))
			 'project 'orgmine-fetch-project nil)))

(defun orgmine-ediff (arg)
  "Run Ediff on local entry and Redmine server entry.
Then entry could be an issue, version, tracker or project."
  (interactive "P")
  (save-excursion
    (unless (outline-on-heading-p t)
      (outline-previous-heading))
    (let ((tags (org-get-tags)))
      (cond ((member orgmine-tag-version tags) (orgmine-ediff-version arg))
	    ((member orgmine-tag-tracker tags) (orgmine-ediff-tracker arg))
	    ((member orgmine-tag-project tags) (orgmine-ediff-project arg))
	    (t (orgmine-ediff-issue arg))))))

;;;;

(defun orgmine-insert-todo-sequence-template ()
  (let* ((issue-statuses (elmine/get-issue-statuses))
	 open-statuses closed-statuses)
    (mapc (lambda (status)
	    (let ((name (orgmine-name status nil t)))
	      (if (plist-get status :is_closed)
		  (add-to-list 'closed-statuses name)
		(add-to-list 'open-statuses name))))
	  (nreverse issue-statuses))
    (insert "#+SEQ_TODO: " (mapconcat 'identity open-statuses " "))
    (if closed-statuses
	(insert " | " (mapconcat 'identity closed-statuses " ")))
    (insert "\n")))

(defun orgmine-insert-assigned-to-property-template ()
  (let* ((users (elmine/get-users))
	 (list (mapcar (lambda (user)
			 (orgmine-idname user orgmine-user-name-format t))
		       users)))
    (insert "#+PROPERTY: om_assigned_to_ALL "
	    (mapconcat 'identity list " ")
	    "\n")))

(defun orgmine-insert-status-property-template ()
  (let* ((statuses (elmine/get-issue-statuses))
	 (list (mapcar (lambda (status)
			 (orgmine-idname status nil t))
		       statuses)))
    (insert "#+PROPERTY: om_status_ALL "
	    (mapconcat 'identity list " ")
	    " opne locked closed"	; for fixed_version
	    "\n")))

(defun orgmine-insert-tracker-property-template (project)
  (let* ((trackers (elmine/get-project-trackers project))
	 (list (mapcar (lambda (tracker)
			 (orgmine-idname tracker nil t))
		       trackers)))
    (insert "#+PROPERTY: om_trackers_ALL "
	    (mapconcat 'identity list " ")
	    "\n")))

(defun orgmine-insert-custom-fields-property-template (project)
  (let ((fields (elmine/get-custom-fields (list :project project))))
    (mapc (lambda (field)
	    (let ((field-format (plist-get field :field_format))
		  (customized-type (plist-get field :customized_type))
		  (possible-values (plist-get field :possible_values)))
	      (cond ((equal field-format "list")
		     (insert "#+PROPERTY: "
			     (orgmine-custom-field-property-name field)
			     "_ALL")
		     (mapc (lambda (elem)
			     (insert " " (plist-get elem :value)))
			   possible-values)
		     (insert "\n"))
		    )))
	  fields)))

(defun orgmine-insert-template (arg)
  "Insert template property footnote for orgmine-mode at current position."
  (interactive "P")
  (let ((project (orgmine-read-project)))
    (orgmine-insert-todo-sequence-template)
    (if (and (boundp 'orgmine-server) orgmine-server)
	(insert "#+PROPERTY: om_server " orgmine-server "\n"))
    (insert "#+PROPERTY: om_project " project "\n")
    (orgmine-insert-status-property-template)
    (orgmine-insert-tracker-property-template (string-to-number project))
    (orgmine-insert-assigned-to-property-template)
    (insert "#+PROPERTY: om_done_ration_ALL "
	    "0 10 20 30 40 50 60 70 80 90 100\n")
    (orgmine-insert-custom-fields-property-template project)))

;;;;

;; (defun orgmine-body-block-before-subtree ()
;;   (org-back-to-heading t)
;;   (show-subtree)
;;   (save-excursion
;;     (forward-line)
;;     (if (not (org-at-heading-p t))
;;         (cons (point)
;;               (outline-next-heading)))))

(defun orgmine-skeletonize-headline (type property-list todo-keyword)
  "Make the current headline into a skeleton headline.
TYPE is any of 'issue, 'fixed_version, 'tracker, 'project.
All properties are removed but PROPERTY-LIST.
If TODO-KEYWORD is not null, set TODO Keyword to TODO-KEYWORD."
  (unless (org-at-heading-p t) (error "not a headline."))
  (show-subtree)
  (let ((properties (orgmine-get-properties nil property-list))
        (title (orgmine-extract-subject
                (substring-no-properties (org-get-heading t t))))
;;         (block (orgmine-body-block-before-subtree)))
        (block (orgmine-body-region)))
    (if block
        (delete-region (car block) (cdr block)))
    (orgmine-update-title title)
    (org-toggle-tag org-archive-tag 'off)
    (org-toggle-tag orgmine-tag-create-me 'on)
    (orgmine-set-properties type properties property-list)
    (if todo-keyword
        (orgmine-todo todo-keyword))))

(defun orgmine-skeletonize-issue (property-list)
  "Make the current issuen entry into a skeleton entry."
  (or property-list
      (setq property-list '(tracker assigned_to custom_fields)))
  (orgmine-current-issue-heading)
  (orgmine-skeletonize-headline 'issue property-list
                                (orgmine-default-todo-keyword))
  ;; remove attachment node and journals node
  (let* ((subtree (orgmine-subtree-region))
         (beg (car subtree))
         (end (copy-marker (cdr subtree))))
    (org-goto-first-child)
    (orgmine-delete-headline orgmine-tag-attachments end t)
    (orgmine-delete-headline orgmine-tag-journals end t)
    (set-marker end nil)
    (goto-char beg)))

(defun orgmine-skeletonize-version (property-list)
  "Make the current issuen entry into a skeleton entry."
  (let ((version (orgmine-find-headline-ancestor orgmine-tag-version)))
    (goto-char (org-element-property :begin version)))
  (orgmine-skeletonize-headline 'fixed_version property-list nil))

(defun orgmine-skeletonize-tracker (property-list)
  "Make the current tracker entry into a skeleton entry."
  (or property-list
      (setq property-list '(tracker)))
  (let ((tracker (orgmine-find-headline-ancestor orgmine-tag-tracker)))
    (goto-char (org-element-property :begin tracker)))
  (orgmine-skeletonize-headline 'tracker property-list nil))

(defun orgmine-skeletonize-project (property-list)
  "Make the current project entry into a skeleton entry."
  (let ((project (orgmine-find-headline-ancestor orgmine-tag-project)))
    (goto-char (org-element-property :begin project)))
  (orgmine-skeletonize-headline 'project property-list nil))

(defun orgmine-skeletonize-region (beg end arg)
  (interactive "r\nP")
  (if (and (org-called-interactively-p 'interactive)
	   (not (org-region-active-p)))
      (error "region not active"))
  (setq end (copy-marker end))
  (org-with-wide-buffer
   (goto-char beg)
   (show-subtree)
   (while (re-search-forward "^\\*+ " end t)
     (save-excursion
       (let ((tags (org-get-tags)))
         (cond ((member orgmine-tag-issue tags)
                (orgmine-skeletonize-issue nil))
               ((member orgmine-tag-version tags)
                (orgmine-skeletonize-version nil))
               ((member orgmine-tag-tracker tags)
                (orgmine-skeletonize-tracker nil))
               ((member orgmine-tag-project tags)
                (orgmine-skeletonize-project nil)))))
     (outline-next-heading))
   (set-marker end nil)
   (goto-char beg)))

(defun orgmine-skeletonize-subtree (arg)
  "Skeletonize the current subtree."
  (interactive "P")
  (let* ((subtree (orgmine-subtree-region))
         (beg (car subtree))
         (end (cdr subtree)))
    (orgmine-skeletonize-region beg end arg)))


;;;;

(defun orgmine-after-todo-state-change ()
  (when (and (boundp 'orgmine-tag-issue)
	     (boundp 'orgmine-tag-update-me)
	     (member orgmine-tag-issue (org-get-tags)))
    (org-toggle-tag orgmine-tag-update-me 'on)
    (message "run M-x orgmine-submit to send the changes to Redmine server.")))
;; (defun orgmine-after-todo-state-change ()
;;   (if (and (org-called-interactively-p 'interactive) ; XXX
;; 	   (member orgmine-tag-issue (org-get-tags)))
;;       (org-toggle-tag orgmine-tag-update-me 'on)))

(provide 'orgmine)

;; orgmine.el ends here
