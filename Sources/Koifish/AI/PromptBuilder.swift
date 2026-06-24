import Foundation

/// Turns a focused-field context + the user's style into a generation request.
/// The key to relevance: feed the model the *surrounding* window context (the
/// conversation/page being replied to), marked at the cursor, and instruct it to
/// reply to the other person and ground every detail in what's actually visible.
/// Prompt wording is original to Koifish.
enum PromptBuilder {
    static func build(
        context: FocusedContext,
        styleDescription: String,
        model: String,
        recentActivity: String = "",
        userBrief: String = "",
        selfName: String = ""
    ) -> GenerationRequest {
        GenerationRequest(
            systemPrompt: systemPrompt(styleDescription: styleDescription, userBrief: userBrief, selfName: selfName),
            userPrompt: userPrompt(context: context, recentActivity: recentActivity),
            model: model
        )
    }

    private static func systemPrompt(styleDescription: String, userBrief: String, selfName: String) -> String {
        var s = """
        You generate the exact text the user should type next, to be inserted at \
        their cursor. You are writing as the user, in their voice.

        Rules:
        - Write what the user should say next to the person they're talking to. \
        Never address the user, and never write a response aimed back at them.
        - The context shows the on-screen conversation. Where the app exposes it, \
        each line is prefixed with who said it — "Me:" is the user, a name is the \
        person they're talking to. Lines marked "Me:" are already sent: don't answer \
        them and don't restate them. If the user's own line is the most recent one, \
        the conversation is waiting on the other side, so write a fresh follow-up \
        rather than a reply. Where prefixes are missing, infer the speakers from the \
        back-and-forth.
        - Keep every concrete detail — names, dates, numbers, facts, promises — tied \
        to what's shown in the inputs below. When the reply seems to need something \
        that isn't there, don't fabricate it: keep that part general or drop it. A \
        made-up detail that reads as plausible is the worst outcome.
        - Match the language, tone, and formality of the surrounding conversation.
        - Fit the destination: full sentences in an email or doc, code inside an \
        editor, something short and casual in a chat or comment field. Whatever you \
        write lands verbatim where the cursor is, so skip wrapping quotes or code \
        fences unless that field would genuinely contain them.
        - Output ONLY the text to insert — no preamble, no "Here is…", no commentary. \
        Add a greeting or sign-off only if the context clearly calls for one. If the \
        field already contains the user's signature or sign-off (a name, "Mvh", "Med \
        vänlig hälsning", "Best", "/Name", etc.), do NOT write your own — give just the \
        message body and leave their existing signature untouched.

        Keep it SHORT. Say the one thing that needs saying and stop. Most replies \
        are a sentence or two; match the length of what you're replying to and never \
        pad to seem thorough. When in doubt, cut it down.

        Sound like a real person, not an assistant. Avoid these AI tells:
        - openers like "I hope this finds you well", "I wanted to reach out", \
        "Thanks for reaching out", "Certainly!", "Great question"
        - closers like "Let me know if you have any questions", "Feel free to…", \
        "I'm happy to help", "Looking forward to hearing from you"
        - hedging and filler: "just", "I think", "definitely", "in order to", \
        "that being said", "it's worth noting"
        - inflated words where a plain one works: use "use" not "utilize", "about" \
        not "regarding", "help" not "assist", "so" not "therefore"
        - lists, headers, and em-dash pile-ups in what should be a casual message
        Use contractions. Vary sentence length. Be specific and direct. No emoji \
        unless the conversation already uses them. Write the way the user actually \
        writes — slightly imperfect and natural beats polished and generic.
        """
        let brief = UserBrief(userBrief).promptBlock
        if !brief.isEmpty {
            s += "\n\n" + brief
        }
        let name = selfName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            s += "\n\nYou are writing as \(name)."
        }
        // The user's own earlier messages in THIS conversation are the best guide to how
        // they write here — and they're already in the captured context (the "Me:" lines,
        // or, in email etc., messages from the name above). Point the model at those
        // instead of re-sending them: costs one sentence, not duplicated tokens.
        let whose = name.isEmpty ? "the user's own" : "\(name)'s"
        s += "\n\nWhen \(whose) earlier messages are visible in the conversation, mirror that voice closely — length, greeting, sign-off, formality, punctuation, emoji. That's the truest guide to how they write here; prefer it over any general style note."
        let trimmed = styleDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            s += "\n\nThe user's writing style (mirror it):\n\(trimmed)"
        }
        return s
    }

    private static func userPrompt(context: FocusedContext, recentActivity: String) -> String {
        var lines: [String] = []
        lines.append("App: \(context.appName)")
        if !context.windowTitle.isEmpty { lines.append("Window: \(context.windowTitle)") }
        if !context.breadcrumb.isEmpty {
            lines.append("Location: \(context.breadcrumb.joined(separator: " › "))")
        }

        if !recentActivity.isEmpty {
            lines.append("""

            Recent activity in OTHER windows you were just in (background only — use \
            it to fill in facts the focused window doesn't show; the other person did \
            NOT see this and you must not quote or reference it as if they did):
            \"\"\"
            \(recentActivity)
            \"\"\"
            """)
        }

        if !context.pageContext.isEmpty {
            lines.append("""

            Visible context — the conversation/page as captured from the screen, \
            including both the other person's messages and the user's own. \
            \(AXContext.cursorMarker) marks the compose box where the user is about \
            to type:
            \"\"\"
            \(context.pageContext)
            \"\"\"
            """)
        }

        let draft = context.fieldText.trimmingCharacters(in: .whitespacesAndNewlines)

        if context.hasSelection {
            lines.append("""

            The user highlighted this text to be rewritten in their voice. Hand back \
            only the rewritten version of the highlighted part — nothing before or \
            after it, and leave the text on either side untouched:
            \(context.selectedText)
            """)
        } else if !draft.isEmpty {
            lines.append("""

            The user has started this text / given this instruction in the field. \
            If it's an instruction (e.g. "reply saying I'm in"), carry it out using \
            the visible context as the source of truth. If it's a partial draft, \
            continue or complete it. Return only the text to insert:
            \(draft)
            """)
        } else {
            lines.append("""

            The field is empty. Write the appropriate reply to the other person, \
            grounded in the visible context above. If there's nothing to reply to, \
            draft a natural opening message for this app.
            """)
        }
        return lines.joined(separator: "\n")
    }
}
