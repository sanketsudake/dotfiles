;; Sanket Sudake
(require 'cask "~/.cask/cask.el")
(cask-initialize)

;; Disable Arrow Keys
(global-set-key (kbd "<up>") 'disabled-key)
(global-set-key (kbd "<down>") 'disabled-key)
(global-set-key (kbd "<left>") 'disabled-key)
(global-set-key (kbd "<right>") 'disabled-key)
(global-set-key (kbd "<home>") 'disabled-key)
(global-set-key (kbd "<end>") 'disabled-key)

;; Set No UI
(dolist (mode '(menu-bar-mode tool-bar-mode scroll-bar-mode))
  (when (fboundp mode) (funcall mode -1)))

;; yes or no becomes y or n
(defalias 'yes-or-no-p 'y-or-n-p)

;; Coding style
(prefer-coding-system 'utf-8)
(prefer-coding-system 'utf-8)
(set-language-environment 'UTF-8)
(set-default-coding-systems 'utf-8)
(setq file-name-coding-system 'utf-8)
(setq buffer-file-coding-system 'utf-8)
(setq coding-system-for-write 'utf-8)
(set-keyboard-coding-system 'utf-8)
(set-terminal-coding-system 'utf-8)
(set-clipboard-coding-system 'utf-8)
(set-selection-coding-system 'utf-8)
(setq default-process-coding-system '(utf-8 . utf-8))

;; Completion ignores filenames ending in any string in this list.
(setq completion-ignored-extensions
      '(".o" ".elc" "~" ".bin" ".class" ".exe" ".ps" ".abs" ".mx"
        ".~jv" ".rbc" ".pyc" ".beam" ".aux" ".out" ".pdf"))


;; Mode tweaks
;;


;;;; Text mode and Auto Fill mode
(setq default-major-mode 'text-mode)
(add-hook 'text-mode-hook 'turn-on-auto-fill)

(require 'volatile-highlights)
(volatile-highlights-mode t)
(autoload 'enable-paredit-mode "paredit"
  "Turn on pseudo-structural editing of Lisp code." t)

;;;; Ido mode
(setq ido-enable-flex-matching t)
(setq ido-everywhere t)
;;This tab override shouldn't be necessary given ido's default
;;configuration, but minibuffer-complete otherwise dominates the
;;tab binding because of my custom tab-completion-everywhere
;;configuration.
(add-hook 'ido-setup-hook
          (lambda ()
            (define-key ido-completion-map [tab] 'ido-complete)))
(ido-mode 1)
(setq ido-vertical-mode t)

;;;; Stop autobackup
;;stop creating those backup~ files
(setq make-backup-files nil)
;;stop creating those #autosave# files
(setq auto-save-default nil)

;;;; autopair mode
(require 'autopair)
(autopair-global-mode 1)
(setq autopair-autowrap t)

;; Save emacs session before exit
(setq desktop-save 'if-exists)
(desktop-save-mode 1)

;; Powerline Mode
(require 'powerline)
(powerline-default-theme)

;;;; Popup switcher
(require 'popup-switcher)
(global-set-key [f2] 'psw-switch-buffer)
(define-key global-map (kbd "C-+") 'text-scale-increase)
(define-key global-map (kbd "C--") 'text-scale-decrease)


;;; cc mode setup
(require 'cc-mode)
(setq-default c-basic-offset 4 c-default-style "linux")
;;(setq-default tab-width 4 indent-tabs-mode t)
(define-key c-mode-base-map (kbd "RET") 'newline-and-indent)
(setq indent-tabs-mode nil)

;; autocomplete and yasnippet mode
(require 'yasnippet)
(yas-global-mode 1)
(require 'auto-complete)
(require 'auto-complete-config)
(ac-config-default)
(ac-flyspell-workaround)
(add-to-list 'ac-dictionary-directories
             "~/.emacs.d/dict")

(setq ac-ignore-case 'smart)
(set-face-background 'ac-candidate-face "lightgray")
(set-face-underline 'ac-candidate-face "darkgray")
(set-face-background 'ac-selection-face "steelblue")
(defun ac-cc-mode-setup ()
  (setq ac-sources '(
		     ac-source-words-in-buffer
		     ac-source-words-in-same-mode-buffers
		     ac-source-filename
		     ac-source-files-in-current-dir
		     ac-source-yasnippet
		     ac-source-dictionary
		     ac-source-semantic
		     ac-source-gtags
		     ac-source-css-property
		     )))
(defun my-ac-config ()
  (add-hook 'c-mode-common-hook 'ac-cc-mode-setup)
  (add-hook 'c++-mode-common-hook 'ac-cc-mode-setup)
  (add-hook 'auto-complete-mode-hook 'ac-common-setup)
  (global-auto-complete-mode t))
(my-ac-config)
(setq ac-use-menu-map t)
;; Default settings
(define-key ac-menu-map "\C-n" 'ac-next)
(define-key ac-menu-map "\C-p" 'ac-previous)

;;;; Eldoc mode
(setq c-eldoc-includes "`pkg-config gtk+-2.0 --cflags` -I./ -I../ -I/usr/include/opencv -I/usr/include/GL -I/usr/include")
(load "c-eldoc")
(add-hook 'c-mode-hook 'c-turn-on-eldoc-mode)
(add-hook 'c++-mode-hook 'c-turn-on-eldoc-mode)

(global-linum-mode 1)
;;(highlight-tabs)
;;(highlight-trailing-whitespace)
