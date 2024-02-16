;;; tlon-babel-ai.el --- AI functionality for the Babel project -*- lexical-binding: t -*-

;; Copyright (C) 2024

;; Author: Pablo Stafforini
;; Homepage: https://github.com/tlon-team/tlon-babel
;; Version: 0.1

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; AI functionality for the Babel project.

;;; Code:

(require 'gptel)
(require 'gptel-extras)
(require 'tlon-babel)

;;;; Variables

(defconst tlon-babel-ai-string-wrapper
  ":\n\n```\n%s\n```\n\n"
  "Wrapper for strings to be passed in prompts.")

(defconst tlon-babel-gptel-error-message
  "`gptel' failed with message: %s"
  "Error message to display when `gptel-quick' fails.")

(defconst tlon-babel-ai-detect-language-prompt
  (format "Please guess the language of the work described in following BibLaTeX entry:%s. Your answer should just be the language of the entry. For example, if you conclude that the entry is in English, your answer should be just 'english'. Moreover, your answer can be only one of the following languages: %s" tlon-babel-ai-string-wrapper
	  (mapconcat 'identity (mapcar 'car bibtex-extras-valid-languages) ", "))
  "Prompt for language detection.")

(defconst tlon-babel-ai-translate-prompt
  (format "Translate the following text into Spanish:%s" tlon-babel-ai-string-wrapper)
  "Prompt for translation.")

;; TODO: generalize to arbitrary langs
(defconst tlon-babel-ai-translate-variants-prompt
  (format "Please generate the best ten Spanish translations of the following English text:%s. Please return each translation on the same line, separated by '|'. Do not add a space either before or after the '|'. Do not precede your answer by 'Here are ten Spanish translations' or any comments of that sort: just return the translations. An example return string for the word 'very beautiful' would be: 'muy bello|muy bonito|muy hermoso|muy atractivo' (etc). Thanks!" tlon-babel-ai-string-wrapper)
  "Prompt for translation variants.")

(defconst tlon-babel-ai-rewrite-prompt
  (format "Por favor, genera las mejores diez variantes del siguiente texto castellano:%s. Por favor, devuelve todas las variantes en una única linea, separadas por '|'. No insertes un espacio ni antes ni después de '|'. No agregues ningún comentario aclaratorio: solo necesito la lista de variantes. A modo de ejemplo, para la expresión 'búsqueda de poder' el texto a devolver sería: 'ansia de poder|ambición de poder|búsqueda de autoridad|sed de poder|afán de poder|aspiración de poder|anhelo de poder|deseo de control|búsqueda de dominio|búsqueda de control' (esta lista solo pretende ilustrar el formato en que debes presentar tu respuesta). Gracias!" tlon-babel-ai-string-wrapper)
  "Prompt for rewriting.")

(defconst tlon-babel-ai-summarize-common-prompts
  `((:prompt "The abstract should be only one paragraph long and it need not mention bibliographic data of the reused work (such as title or author). Write the abstract directly stating what the article argues, rather than using phrases such as 'The article argues that...'. For example, instead of writing 'The article tells that mankind fought smallpox for centuries...', write 'Mankind fought smallpox for centuries...'. Also, please omit any disclaimers of the form 'As an AI language model, I'm unable to browse the internet in real-time.' I understand that you may sometimes have to create an abstract simply by inferring its contents from the BibTeX entry. Just give me this abstract without any disclaimers. Finally, end your abstract with the phrase ' – Abstract generated by GPT-4.' For example, if your abstract is 'Mankind fought smallpox for centuries...', your final abstract should be 'Mankind fought smallpox for centuries... – Abstract generated by GPT-4.'"
	     :language "en")
    ;; TODO: update translation to match English version
    (:prompt "El resumen debe tener solamente un párrafo y no es necesario que mencione datos bibliográficos de la obra reusmida (como título o autor). Escribe el resumen afirmando directamente lo que el artículo sostiene, en lugar de utilizar giros como ‘El artículo sostiene que...’. Por ejemplo, en lugar de escribir ‘El artículo cuenta que la humanidad luchó contra la viruela durante siglos...’, escribe ‘La humanidad luchó contra la viruela durante siglos...’"
	     :language "es"))
  "Prompts for summarization common elements.")

(defconst tlon-babel-ai-summarize-prompts
  `((:prompt ,(format "Please generate an abstract of the following article:%s. %s" tlon-babel-ai-string-wrapper
		      (tlon-babel-lookup tlon-babel-ai-summarize-common-prompts :prompt :language "en"))
	     :language "en")
    (:prompt ,(format "Por favor, genera un resumen del siguiente artículo:%s. %s" tlon-babel-ai-string-wrapper
		      (tlon-babel-lookup tlon-babel-ai-summarize-common-prompts :prompt :language "en"))
	     :language "es"))
  "Prompts for summarization.")

(defconst tlon-babel-ai-summarize-biblatex-prompts
  `((:prompt ,(format "Please provide an abstract of the work described by the following BibLaTeX entry:%s. It is likely that there is already an abstract of the work available online: use the URL, DOI or ISBN in the entry, or other fields if those are unavailable, to locate the abstract from an official or authoritative source (such as the journal in which the work was published or the Library of Congress entry). If you can’t find an abstract, create one yourself. %s"
		      tlon-babel-ai-string-wrapper
		      (tlon-babel-lookup tlon-babel-ai-summarize-common-prompts :prompt :language "en"))
	     :language "en")
    ;; TODO: update translation to match English version
    (:prompt ,(format "Por favor, genera un resumen del artículo que describe la siguiente entrada de BibLaTeX:%s. %s"
		      tlon-babel-ai-string-wrapper
		      (tlon-babel-lookup tlon-babel-ai-summarize-common-prompts :prompt :language "es"))
	     :language "es"))
  "Prompts for biblate summarization.")

;;;; Functions

;;;;; General

(defun tlon-babel-make-gptel-request (prompt string &optional callback)
  "Make a `gptel' request with PROMPT and STRING and CALLBACK.
If CALLBACK is nil, use `tlon-babel-ai-generic-callback'."
  (let ((callback (or callback #'tlon-babel-ai-generic-callback)))
    (gptel-request (format prompt string) :callback callback)))

(defun tlon-babel-ai-generic-callback (response info)
  "Generic callback function for AI requests.
RESPONSE is the response from the AI model and INFO is the response info."
  (if (not response)
      (tlon-babel-ai-callback-fail info)
    response))

(defun tlon-babel-ai-callback-fail (info)
  "Callback message when `gptel' fails.
INFO is the response info."
  (message tlon-babel-gptel-error-message (plist-get info :status)))

;;;;; Translation

;;;;;; Translation variants

;;;###autoload
(defun tlon-babel-ai-translate (string)
  "Return ten alternative translations of STRING."
  (interactive "sText to translate: ")
  (tlon-babel-make-gptel-request tlon-babel-ai-translate-variants-prompt string
				 #'tlon-babel-ai-translate-callback))

(defun tlon-babel-ai-translate-callback (response info)
  "Callback for `tlon-babel-ai-translate'.
RESPONSE is the response from the AI model and INFO is the response info."
  (if (not response)
      (tlon-babel-ai-callback-fail info)
    (let ((translations (split-string response "|")))
      (kill-new (completing-read "Translation: " translations)))))

;;;;;; File translation

(defun tlon-babel-ai-translate-file (file)
  "Translate FILE."
  (let* ((string (with-temp-buffer
		   (insert-file-contents file)
		   (buffer-string))))
    (tlon-babel-make-gptel-request tlon-babel-ai-translate-prompt string
				   (lambda (response info)
				     (tlon-babel-ai-translate-file-callback response info file)))))

(defun tlon-babel-ai-translate-file-callback (response info file)
  "Callback for `tlon-babel-ai-translate-file'.
RESPONSE is the response from the AI model and INFO is the response info. FILE
is the file to translate."
  (if (not response)
      (tlon-babel-ai-callback-fail info)
    (let* ((counterpart (tlon-babel-get-counterpart file))
	   (filename (file-name-nondirectory counterpart))
	   (target-path (concat
			 (file-name-sans-extension filename)
			 "--ai-translated.md")))
      (with-temp-buffer
	(insert response)
	(write-region (point-min) (point-max) target-path)))))

;;;;; Rewriting

;;;###autoload
(defun tlon-babel-ai-rewrite ()
  "Docstring."
  (interactive)
  (let* ((string (if (region-active-p)
		     (buffer-substring-no-properties (region-beginning) (region-end))
		   (read-string "Text to rewrite: "))))
    (gptel-request
	(format tlon-babel-ai-rewrite-prompt string)
      :callback
      (lambda (response info)
	(if (not response)
	    (message tlon-babel-gptel-error-message (plist-get info :status))
	  (let* ((variants (split-string response "|"))
		 (variant (completing-read "Variant: " variants)))
	    (delete-region (region-beginning) (region-end))
	    (kill-new variant)))))))

;;;;; Summarization

;;;###autoload
(defun tlon-babel-ai-summarize (model)
  "Summarize and copy the summary to the kill ring using AI MODEL.
If region is active, summarize the region; otherwise, prompt for a file to
summarize."
  (interactive (list (completing-read "Model: " gptel-extras-backends)))
  (gptel-extras-model-config model)
  (let* ((current-file (buffer-file-name))
	 (string
	  (if (region-active-p)
	      (buffer-substring-no-properties (region-beginning) (region-end))
	    (let* ((selected-file (read-file-name "Select file to summarize (if you would like to summarize a region, run this command with an active region): " nil current-file nil (file-name-nondirectory current-file))))
	      (with-temp-buffer
		(insert-file-contents selected-file)
		(buffer-string)))))
	 (repo (tlon-babel-get-repo-from-file current-file))
	 (language (tlon-babel-repo-lookup :language :dir repo))
	 (prompt (tlon-babel-lookup tlon-babel-ai-summarize-prompts :prompt :language language)))
    (message "Generating summary. This may take 5–30 seconds, depending on length...")
    (gptel-request
	(format prompt string)
      :callback
      (lambda (response info)
	(if (not response)
	    (message "`gptel' failed with message: %s" (plist-get info :status))
	  (kill-new response)
	  (message "Copied AI-generated summary to the kill ring:\n\n%s" response))))))
;;;;;; BibLaTeX summarization

(defun tlon-babel-ai-summarize-biblatex (&optional string)
  "Summarize the work described in the BibLaTeX STRING using AI.
If STRING is nil, use the current entry."
  (interactive)
  (let ((string (or string (bibtex-extras-get-entry-as-string))))
    (unless (bibtex-extras-get-field-in-string string "abstract")
      (when-let* ((language (bibtex-extras-get-field "langid"))
		  (lang-short (bibtex-extras-get-two-letter-code language)))
	(if-let ((prompt (tlon-babel-lookup tlon-babel-ai-summarize-biblatex-prompts :prompt :language lang-short)))
	    (tlon-babel-make-gptel-request prompt string #'tlon-babel-ai-summarize-biblatex-callback)
	  (user-error "No prompt defined in `tlon-babel-ai-summarize-prompts' for language %s" language))))))

(defun tlon-babel-ai-summarize-biblatex-callback (response info)
  "Callback for `tlon-babel-ai-summarize-biblatex'.
RESPONSE is the response from the AI model and INFO is the response info."
  (if (not response)
      (tlon-babel-ai-callback-fail info)
    (let ((key (bibtex-extras-get-field "=key=")))
      (bibtex-set-field "abstract" response)
      (message "Set abstract of `%s' to %s" key response)
      (bibtex-next-entry)
      (tlon-babel-ai-summarize-biblatex))))


(provide 'tlon-babel-ai)
;;; tlon-babel-ai.el ends here

;; Local Variables:
;; jinx-languages: "es en"
;; End:
