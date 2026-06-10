;;; matugen-theme.el --- Dynamic theme switcher using Matugen colors -*- lexical-binding: t -*-

;; Copyright (C) 2026 Diego

;; Author: Diego
;; Maintainer: Diego
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (modus-themes "4.0"))
;; Keywords: themes, matugen, wayland, ricing

;;; Commentary:

;; Este paquete permite integrar la paleta de colores generada por `matugen`
;; directamente con tu Emacs usando `modus-themes`.
;; Matugen debe configurarse para exportar un archivo JSON con los colores.
;; Cuando el archivo JSON cambia, este paquete recarga automáticamente
;; tu tema.

;;; Code:

(require 'json)
(require 'filenotify)
(require 'modus-themes)

(defgroup matugen-theme nil
  "Dynamic theme switcher based on Matugen color palettes."
  :group 'modus-themes
  :prefix "matugen-theme-")

(defcustom matugen-theme-colors-file (expand-file-name "~/.cache/matugen-colors.json")
  "Ruta al archivo JSON generado por Matugen."
  :type 'file
  :group 'matugen-theme)

(defcustom matugen-theme-style 'accent
  "Estilo de integración de la paleta.
Puede ser `accent` para cambiar solo los acentos (mantiene el contraste de Modus)
o `full` para sobreescribir el fondo y toda la paleta con los colores de Matugen."
  :type '(choice (const :tag "Solo acentos" accent)
                 (const :tag "Tema completo" full))
  :group 'matugen-theme)

(defvar matugen-theme--file-watch-descriptor nil
  "Descriptor para el file watcher del JSON de colores.")

(defun matugen-theme--read-colors ()
  "Lee el archivo JSON de colores y lo devuelve como alist."
  (when (file-exists-p matugen-theme-colors-file)
    (let ((json-object-type 'alist)
          (json-array-type 'list)
          (json-key-type 'symbol))
      (json-read-file matugen-theme-colors-file))))

;;;###autoload
(defun matugen-theme-apply-accent ()
  "Aplica la paleta de Matugen solo a los acentos de `modus-themes`."
  (interactive)
  (let ((colors (matugen-theme--read-colors)))
    (when colors
      (let ((primary (cdr (assq 'primary colors)))
            (secondary (cdr (assq 'secondary colors)))
            (tertiary (cdr (assq 'tertiary colors)))
            (error (cdr (assq 'error colors))))
        (setq modus-themes-common-palette-overrides
              `((blue ,primary)
                (cyan ,secondary)
                (magenta ,tertiary)
                (red ,error)
                (blue-cooler ,primary)
                (blue-warmer ,secondary)
                (magenta-cooler ,tertiary)))
        (when (modus-themes--current-theme)
          (modus-themes-load-theme (modus-themes--current-theme)))
        (message "Matugen: Acentos aplicados.")))))

;;;###autoload
(defun matugen-theme-apply-full ()
  "Aplica la paleta completa de Matugen a `modus-themes` (fondos, bordes, etc)."
  (interactive)
  (let ((colors (matugen-theme--read-colors)))
    (when colors
      (let ((primary (cdr (assq 'primary colors)))
            (secondary (cdr (assq 'secondary colors)))
            (tertiary (cdr (assq 'tertiary colors)))
            (error (cdr (assq 'error colors)))
            (bg (cdr (assq 'background colors)))
            (fg (cdr (assq 'on_background colors)))
            (surface (cdr (assq 'surface colors)))
            (surface-var (cdr (assq 'surface_variant colors))))
        (setq modus-themes-common-palette-overrides
              `((bg-main ,bg)
                (fg-main ,fg)
                (bg-dim ,surface)
                (bg-alt ,surface-var)
                (border ,surface-var)
                (blue ,primary)
                (cyan ,secondary)
                (magenta ,tertiary)
                (red ,error)
                (blue-cooler ,primary)
                (blue-warmer ,secondary)
                (magenta-cooler ,tertiary)))
        (when (modus-themes--current-theme)
          (modus-themes-load-theme (modus-themes--current-theme)))
        (message "Matugen: Tema completo aplicado.")))))

;;;###autoload
(defun matugen-theme-reload ()
  "Recarga la paleta según el estilo configurado."
  (interactive)
  (if (eq matugen-theme-style 'full)
      (matugen-theme-apply-full)
    (matugen-theme-apply-accent)))

(defun matugen-theme--watcher-callback (event)
  "Callback que se ejecuta cuando el archivo de colores cambia."
  ;; file-notify events usually look like (descriptor action file . info)
  ;; where action is 'changed, 'created, 'attribute-changed etc.
  (when (memq (nth 1 event) '(changed attribute-changed created))
    (matugen-theme-reload)))

;;;###autoload
(define-minor-mode matugen-theme-mode
  "Minor mode global para sincronizar Emacs con los colores de Matugen."
  :global t
  :lighter " Matugen"
  (if matugen-theme-mode
      (progn
        ;; Aplicar inicialmente si el archivo existe
        (when (file-exists-p matugen-theme-colors-file)
          (matugen-theme-reload))
        ;; Iniciar watcher
        (unless matugen-theme--file-watch-descriptor
          ;; Asegurarse que el directorio exista
          (let ((dir (file-name-directory matugen-theme-colors-file)))
            (unless (file-exists-p dir)
              (make-directory dir t)))
          (setq matugen-theme--file-watch-descriptor
                (file-notify-add-watch matugen-theme-colors-file
                                       '(change attribute-change)
                                       #'matugen-theme--watcher-callback))))
    ;; Disable mode
    (when matugen-theme--file-watch-descriptor
      (file-notify-rm-watch matugen-theme--file-watch-descriptor)
      (setq matugen-theme--file-watch-descriptor nil))))

(provide 'matugen-theme)
;;; matugen-theme.el ends here
