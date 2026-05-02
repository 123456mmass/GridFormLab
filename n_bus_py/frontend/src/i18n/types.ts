export type Language = "en" | "th";

export interface InterpolationVars {
  [key: string]: string | number;
}

export type Dictionary = Record<string, Record<Language, string>>;
