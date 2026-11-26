import {
  localSnoozeDate,
  localSnoozeTime,
  resolveCustomSnooze,
  type CustomSnoozeInput,
} from "@t3tools/client-runtime/state/thread-settled";
import { msg, useGT, useMessages } from "gt-react-native";
import { useState } from "react";
import { Modal, Pressable, ScrollView, View } from "react-native";

import { AppText } from "../../components/ui/AppText";
import { Button } from "../../components/ui/Button";
import { DateTimePicker } from "../../components/ui/DateTimePicker";
import { NumberField } from "../../components/ui/NumberField";
import { OverlayPortal } from "../../components/ui/OverlayPortal";
import { SegmentedControl } from "../../components/ui/SegmentedControl";
import { useFormattingLocale } from "../../i18n/I18nProvider";

const modes = [
  { value: "date", label: msg("Date and time") },
  { value: "duration", label: msg("Duration") },
] as const;
const units = [
  { value: "minutes", label: msg("Minutes") },
  { value: "hours", label: msg("Hours") },
  { value: "days", label: msg("Days") },
] as const;

export function CustomSnoozeSheet(props: {
  readonly onClose: () => void;
  readonly onSnooze: (snoozedUntil: string) => void;
}) {
  const gt = useGT();
  const m = useMessages();
  const locale = useFormattingLocale();
  const [mode, setMode] = useState<CustomSnoozeInput["mode"]>("date");
  const [date, setDate] = useState(() => new Date(Date.now() + 3_600_000));
  const [picker, setPicker] = useState<"date" | "time" | null>(null);
  const [amount, setAmount] = useState(2);
  const [unit, setUnit] = useState<"minutes" | "hours" | "days">("hours");
  const [error, setError] = useState<string | null>(null);
  const dateLabel = date.toLocaleDateString(locale, { month: "short", day: "numeric" });
  const timeLabel = date.toLocaleTimeString(locale, { hour: "numeric", minute: "2-digit" });

  function submit() {
    const input: CustomSnoozeInput =
      mode === "date"
        ? { mode, date: localSnoozeDate(date), time: localSnoozeTime(date) }
        : { mode, amount: String(amount), unit };
    const snoozedUntil = resolveCustomSnooze(input, new Date());
    if (!snoozedUntil) {
      setError(
        mode === "date"
          ? gt("Choose a date and time in the future.")
          : gt("Enter a positive duration."),
      );
      return;
    }
    props.onSnooze(snoozedUntil);
    props.onClose();
  }

  return (
    <OverlayPortal>
      <Modal transparent animationType="fade" onRequestClose={props.onClose}>
        <View className="flex-1 items-center justify-center px-4">
          <Pressable
            accessible={false}
            className="absolute inset-0 bg-black/50"
            onPress={props.onClose}
          />
          <View className="max-h-[85%] w-full max-w-[360px] overflow-hidden rounded-3xl bg-card-alt">
            <ScrollView keyboardShouldPersistTaps="handled">
              <View className="gap-4 p-6">
                <AppText accessibilityRole="header" textRole="title">
                  {gt("Custom snooze")}
                </AppText>
                <SegmentedControl
                  variant="card"
                  options={modes.map((option) => ({ ...option, label: m(option.label) }))}
                  selected={mode}
                  onSelect={(value) => {
                    setMode(value);
                    setError(null);
                  }}
                />
                {mode === "date" ? (
                  <View className="flex-row flex-wrap gap-2">
                    <Button
                      label={dateLabel}
                      accessibilityLabel={gt("Date, {date}", { date: dateLabel })}
                      onPress={() => setPicker("date")}
                    />
                    <Button
                      label={timeLabel}
                      accessibilityLabel={gt("Time, {time}", { time: timeLabel })}
                      onPress={() => setPicker("time")}
                    />
                  </View>
                ) : (
                  <>
                    <NumberField
                      label={gt("Duration amount")}
                      min={1}
                      max={99}
                      value={amount}
                      onValueChange={setAmount}
                    />
                    <SegmentedControl
                      variant="card"
                      options={units.map((option) => ({ ...option, label: m(option.label) }))}
                      selected={unit}
                      onSelect={setUnit}
                    />
                  </>
                )}
                {error ? (
                  <AppText
                    accessibilityRole="alert"
                    textRole="footnote"
                    className="text-danger-foreground"
                  >
                    {error}
                  </AppText>
                ) : null}
                <View className="flex-row flex-wrap justify-end gap-2">
                  <Button label={gt("Cancel")} tone="text" onPress={props.onClose} />
                  <Button
                    label={gt("Snooze", { $context: "verb, confirm button" })}
                    tone="primary"
                    onPress={submit}
                  />
                </View>
                {picker ? (
                  <DateTimePicker
                    key={picker}
                    mode={picker}
                    value={date}
                    onDismiss={() => setPicker(null)}
                    onSelect={(value) => {
                      setDate(value);
                      setError(null);
                    }}
                  />
                ) : null}
              </View>
            </ScrollView>
          </View>
        </View>
      </Modal>
    </OverlayPortal>
  );
}
