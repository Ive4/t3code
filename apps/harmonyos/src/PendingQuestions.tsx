import {
  buildPendingUserInputAnswers,
  isPendingUserInputOptionSelected,
  setPendingUserInputCustomAnswer,
  togglePendingUserInputOptionSelection,
  type PendingUserInputDraftAnswer,
} from "@t3tools/client-runtime/state/pending-user-input";
import {
  seedUserInputDraftAnswers,
  type ThreadPendingUserInput,
} from "@t3tools/client-runtime/state/thread-requests";
import type { ProviderUserInputAnswers } from "@t3tools/contracts";
import { useState } from "react";
import { Button, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from "react-native";
import { useWorkspaceTheme } from "./WorkspaceUi";

export function PendingQuestions({
  request,
  disabled,
  labels,
  onSubmit,
  onDismiss,
}: {
  request: ThreadPendingUserInput;
  disabled: boolean;
  labels: { answer: string; submitAnswers: string; dismiss: string; requestExpired: string };
  onSubmit: (answers: ProviderUserInputAnswers) => void;
  onDismiss: () => void;
}) {
  const [draft, setDraft] = useState<Record<string, PendingUserInputDraftAnswer>>(() =>
    seedUserInputDraftAnswers(request.questions, {}),
  );
  const answers = buildPendingUserInputAnswers(request.questions, draft);
  const unavailable = request.responseCapability === "not_resumable";
  const theme = useWorkspaceTheme();
  const foreground = { color: theme["--color-foreground"] };
  const muted = { color: theme["--color-foreground-muted"] };
  const border = { borderColor: theme["--color-border-subtle"] };

  return (
    <View style={styles.card}>
      <ScrollView style={styles.questions} keyboardShouldPersistTaps="handled">
        {request.questions.map((question) => (
          <View key={question.id} style={styles.question}>
            <Text style={[styles.heading, foreground]}>{question.question}</Text>
            {question.options.map((option) => {
              const value = option.value ?? option.label;
              const checked = isPendingUserInputOptionSelected(question, draft[question.id], value);
              return (
                <Pressable
                  key={value}
                  accessibilityRole={question.multiSelect ? "checkbox" : "radio"}
                  accessibilityState={{ checked, disabled: disabled || unavailable }}
                  disabled={disabled || unavailable}
                  onPress={() =>
                    setDraft((prior) => ({
                      ...prior,
                      [question.id]: togglePendingUserInputOptionSelection(
                        question,
                        prior[question.id],
                        value,
                      ),
                    }))
                  }
                  style={[
                    styles.option,
                    border,
                    checked && {
                      backgroundColor: theme["--color-thread-selected"],
                      borderColor: theme["--color-focus"],
                    },
                  ]}
                >
                  <Text style={[styles.heading, foreground]}>{option.label}</Text>
                  {option.description !== option.label && (
                    <Text style={muted}>{option.description}</Text>
                  )}
                </Pressable>
              );
            })}
            {question.allowCustomAnswer !== false && (
              <TextInput
                accessibilityLabel={question.question}
                placeholder={labels.answer}
                placeholderTextColor={theme["--color-placeholder"]}
                editable={!disabled && !unavailable}
                multiline
                value={draft[question.id]?.customAnswer ?? ""}
                onChangeText={(answer) =>
                  setDraft((prior) => ({
                    ...prior,
                    [question.id]: setPendingUserInputCustomAnswer(
                      question,
                      prior[question.id],
                      answer,
                    ),
                  }))
                }
                style={[styles.option, border, foreground]}
              />
            )}
          </View>
        ))}
      </ScrollView>
      {unavailable ? (
        <Text style={muted}>{labels.requestExpired}</Text>
      ) : (
        <View style={styles.actions}>
          <Button
            title={labels.submitAnswers}
            disabled={disabled || answers === null}
            onPress={() => {
              if (answers !== null) onSubmit(answers);
            }}
          />
          {request.dismissible && (
            <Button title={labels.dismiss} disabled={disabled} onPress={onDismiss} />
          )}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  card: { gap: 8, paddingHorizontal: 16, paddingBottom: 8 },
  questions: { maxHeight: 280 },
  question: { gap: 6, marginBottom: 10 },
  heading: { fontWeight: "600" },
  option: { borderWidth: 1, borderRadius: 8, padding: 10 },
  actions: { flexDirection: "row", gap: 8 },
});
