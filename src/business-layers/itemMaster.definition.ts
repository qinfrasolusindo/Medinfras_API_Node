import {
  and,
  buildFilterExpression,
  cond,
} from "../core/filter-expression.util";
import { BusinessLayerDefinition } from "./types";

// INI CODE ADALAH SALAH SATU CONTOH DEFINISI BUSINESS LAYER UNTUK "settingParameter".

interface ListBody {
  itemType: string;
}

export const ITEM_TYPE = {
  pelayanan: "X001^001",
  obat: "X001^002",
  alkes: "X001^003",
  lab: "X001^004",
  radiologi: "X001^005",
  penunjang_medis: "X001^006",
  mcu: "X001^007",
  non_medis: "X001^008",
  gizi: "X001^009",
} as const;

type ItemType = keyof typeof ITEM_TYPE;

const itemMaster: BusinessLayerDefinition = {
  name: "itemMaster",
  operations: [
    {
      route: "list",
      summary:
        "Get item master data filtered by item type. Valid item types: pelayanan, obat, alkes, lab, radiologi, penunjang_medis, mcu, non_medis, gizi.",

      example: {
        itemType: "pelayanan",
      },

      validate: (body: ListBody) => {
        const itemType = body.itemType?.trim().toLowerCase();

        if (!itemType) {
          return "itemType is required";
        }

        if (!(itemType in ITEM_TYPE)) {
          return `Invalid itemType '${body.itemType}'. Valid values: ${Object.keys(ITEM_TYPE).join(", ")}`;
        }
        return null;
      },

      method: "GetItemMasterList",

      buildArgs: (body: ListBody) => [
        buildFilterExpression(
          and(
            cond(
              "GCItemType",
              "=",
              ITEM_TYPE[body.itemType.trim().toLowerCase() as ItemType],
            ),
            cond("isdeleted", "=", 0),
          ),
        ),
      ],

      resultShape: "list",
    },
  ],
};

export default itemMaster;
