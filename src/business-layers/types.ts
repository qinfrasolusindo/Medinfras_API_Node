
/**
 * Context yang diberikan ke `handler` custom.
 * Bisa dipakai untuk memanggil .NET BusinessLayer tanpa import langsung.
 */
export interface BusinessLayerContext {
  getBusinessLayer: () => Promise<any>;
  toJson: <T = unknown>(dotnetObject: unknown) => Promise<T>;
  toJsonList: <T = unknown>(dotnetList: unknown[] | null | undefined) => Promise<T[]>;
}

/**
 * Satu operation di dalam business layer.
 *
 * Ada 2 cara implementasi:
 *
 * 1. SIMPLE MODE
 *    Gunakan `method` + `buildArgs`.
 *    Router akan memanggil method .NET dan mengatur hasil sesuai `resultShape`.
 *
 * 2. ADVANCED MODE
 *    Gunakan `handler` untuk kebutuhan yang lebih kompleks,
 *    misalnya join atau beberapa pemanggilan method .NET.
 *
 *    Jika `handler` tersedia, `method` dan `buildArgs` tidak digunakan.
 */
export interface BusinessLayerOperation<TBody = any> {
  /** Route di bawah base path group, misalnya `list`, `get`, atau `insert`. */
  route: string;

  summary?: string;
  example?: TBody;

  /** Validasi request body. Return pesan error jika tidak valid. */
  validate?: (body: TBody) => string | null | undefined;

  // --- simple mode ---

  /** Nama method static BusinessLayer .NET yang akan dipanggil. */
  method?: string;

  /** Mengubah request body menjadi argumen untuk method .NET. */
  buildArgs?: (body: TBody) => unknown[];

  /**
   * Menentukan bentuk hasil dari method .NET:
   * - `list`   -> hasil berupa list, diproses dengan `toJsonList()`
   * - `object` -> hasil berupa object, diproses dengan `toJson()`
   * - `raw`    -> hasil primitive seperti int, bool, atau string
   */
  resultShape?: 'list' | 'object' | 'raw';

  // --- advanced mode ---

  /**
   * Handler custom untuk operasi yang lebih kompleks.
   * Bisa memanggil satu atau beberapa method .NET sekaligus.
   */
  handler?: (body: TBody, ctx: BusinessLayerContext) => Promise<unknown>;
}

/**
 * Group dari beberapa operation yang masih satu business layer.
 *
 * Contoh:
 * - `settingParameter`
 * - `patient`
 *
 * Satu definition = satu group.
 * Satu group bisa memiliki banyak operation seperti get, list, insert,
 * update, delete, atau fungsi lain yang masih berkaitan.
 */
export interface BusinessLayerDefinition {
  /** Nama group yang menjadi base path `/medinfras/api/{name}`. */
  name: string;

  operations: BusinessLayerOperation[];
}
