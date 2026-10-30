;;; matugen-theme-faces.el --- Semantic role to face mapping -*- lexical-binding: t; -*-

;;; Commentary:
;; This module only builds face specifications.  Color policy, contrast checks
;; and activation belong to matugen-theme.el.  No optional package is required.

;;; Code:
(require 'cl-lib)

(defun matugen-theme-faces-build (roles)
  "Build complete face specifications from validated semantic ROLES."
  (let* ((minimal (eq (alist-get 'emphasis roles) 'minimal))
         (vivid (eq (alist-get 'emphasis roles) 'vivid))
         (scale (alist-get 'heading-scale roles))
         (content-accent (if minimal 'text 'accent))
         (keyword-weight (if minimal 'normal 'bold))
         specs)
    (cl-labels
        ((emit (faces foreground background &rest attributes)
           (dolist (face (if (listp faces) faces (list faces)))
             (push `(,face ((t ,(append
                                 (when foreground (list :foreground (alist-get foreground roles)))
                                 (when background (list :background (alist-get background roles)))
                                 attributes)))) specs))))
      (emit 'default 'text 'surface)
      (emit '(fringe line-number) 'text-muted 'surface)
      (emit 'line-number-current-line 'text 'surface :weight 'bold)
      (emit 'cursor nil 'cursor)
      ;; Region explicitly replaces syntax foregrounds to preserve contrast.
      (emit '(region secondary-selection) 'selection-fg 'selection-bg :extend t)
      (emit '(hl-line solaire-hl-line-face) nil 'surface-raised :extend t)
      (emit '(vertical-border window-divider window-divider-first-pixel
                              window-divider-last-pixel) 'surface-active 'surface)
      (emit '(shadow completions-annotations) 'text-muted nil)
      (emit '(minibuffer-prompt completions-common-part) 'accent nil :weight 'bold)
      (emit '(link link-visited button) content-accent nil :underline t)
      (emit '(error compilation-error) 'error nil :weight 'bold)
      (emit '(warning compilation-warning) 'warning nil :weight 'bold)
      (emit '(success compilation-info) 'success nil :weight 'bold)

      (dolist (group '(((font-lock-keyword-face font-lock-builtin-face) . keyword)
                       ((font-lock-function-name-face font-lock-function-call-face) . function)
                       ((font-lock-variable-name-face font-lock-variable-use-face) . variable)
                       ((font-lock-type-face) . type)
                       ((font-lock-string-face) . string)
                       ((font-lock-constant-face font-lock-preprocessor-face
                                                  font-lock-number-face) . constant)))
        (emit (car group) (cdr group) nil
              :weight (if (eq (cdr group) 'keyword) keyword-weight 'normal)))
      (emit '(font-lock-comment-face font-lock-comment-delimiter-face font-lock-doc-face
                                     font-lock-doc-markup-face) 'text-muted nil :slant 'normal)
      (emit 'font-lock-warning-face 'warning nil :weight 'bold)
      (emit '(font-lock-negation-char-face font-lock-operator-face
                                         font-lock-punctuation-face font-lock-bracket-face)
            'text nil)

      (dotimes (index 8)
        (let ((role (if minimal 'text
                      (nth (mod index 6) '(function keyword constant type string variable))))
              (height (* scale (cond (minimal 1.0)
                                      ((= index 0) (if vivid 1.15 1.08))
                                      ((= index 1) (if vivid 1.08 1.03))
                                      (t 1.0)))))
          (emit (intern (format "org-level-%d" (1+ index))) role nil :weight 'bold :height height)
          (when (< index 6)
            (emit (intern (format "markdown-header-face-%d" (1+ index))) role nil
                  :weight 'bold :height height))))
      (emit '(org-document-title markdown-header-face) 'text nil :weight 'bold
            :height (* scale (if minimal 1.0 1.15)))
      (emit '(org-document-info org-document-info-keyword org-meta-line org-special-keyword
                               org-property-value org-drawer org-tag org-date
                               markdown-metadata-key-face markdown-metadata-value-face
                               markdown-markup-face markdown-list-face)
            'text-muted nil :slant 'normal)
      (emit '(org-link markdown-link-face markdown-url-face markdown-reference-face)
            content-accent nil :underline t)
      (emit '(org-todo org-checkbox org-priority) (if minimal 'text 'warning) nil :weight 'bold)
      (emit 'org-done (if minimal 'text-muted 'success) nil :weight 'normal)
      (emit '(org-table org-formula) (if minimal 'text 'constant) nil)
      (emit '(org-block markdown-pre-face) 'text 'surface-raised :extend t)
      (emit '(org-block-begin-line org-block-end-line) 'text-muted 'surface-raised :extend t)
      (emit '(org-code markdown-code-face markdown-inline-code-face) 'type 'surface-raised)
      (emit 'org-verbatim 'string 'surface-raised)
      (emit '(org-quote org-verse markdown-blockquote-face) 'text nil :slant 'normal)
      (emit '(org-hide solaire-org-hide-face) 'surface nil)
      (emit 'markdown-bold-face 'text nil :weight 'bold)
      (emit 'markdown-italic-face 'text nil :slant 'italic)

      (emit 'mode-line 'text 'surface-active :box nil)
      (emit 'mode-line-inactive 'text-muted 'surface-raised :box nil)
      (emit '(header-line tab-bar tab-line) 'text 'surface-raised :box nil)
      (emit '(tab-bar-tab tab-line-tab-current) 'selection-fg 'selection-bg :weight 'bold)
      (emit '(tab-bar-tab-inactive tab-line-tab-inactive) 'text-muted 'surface-raised)
      (emit '(corfu-default company-tooltip company-tooltip-common) 'text 'surface-raised)
      (emit '(vertico-current ivy-current-match helm-selection corfu-current
                              company-tooltip-selection isearch match)
            'selection-fg 'selection-bg :weight 'bold)
      (emit '(lazy-highlight query-replace) 'accent 'surface-raised :weight 'bold)
      (emit 'isearch-fail 'error 'surface-raised :weight 'bold)
      (dolist (kind '(error warning success))
        (let ((suffix (if (eq kind 'success) 'info kind)))
          (emit (list (intern (format "flymake-%s" (if (eq kind 'success) "note" kind)))
                      (intern (format "flycheck-%s" suffix))
                      (intern (format "eglot-diagnostic-tag-%s-face" suffix)))
                nil nil :underline `(:style wave :color ,(alist-get kind roles)))
          (emit (intern (format "flycheck-fringe-%s" suffix)) kind nil)))
      (emit '(diff-added diff-refine-added magit-diff-added magit-diff-added-highlight)
            'success 'surface-raised)
      (emit '(diff-removed diff-refine-removed magit-diff-removed magit-diff-removed-highlight)
            'error 'surface-raised)
      (emit '(diff-changed diff-refine-changed) 'warning 'surface-raised)
      (emit '(diff-context magit-diff-context) 'text-muted 'surface)
      (emit '(diff-hunk-header magit-diff-hunk-heading) 'text 'surface-active :weight 'bold)
      (emit '(diff-header diff-file-header magit-diff-file-heading) 'text 'surface-raised :weight 'bold)
      (emit '(doom-dashboard-banner doom-dashboard-menu-title doom-dashboard-footer
                                     doom-dashboard-footer-icon) 'accent nil)
      (emit 'doom-dashboard-menu-desc 'text-muted nil)
      (emit 'solaire-default-face 'text 'surface)
      (emit 'solaire-mode-line-face 'text 'surface-active :box nil)
      (emit 'solaire-mode-line-inactive-face 'text-muted 'surface-raised :box nil))
    (nreverse specs)))

(provide 'matugen-theme-faces)
;;; matugen-theme-faces.el ends here
