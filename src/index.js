import { FastMCP } from "fastmcp";
import { astro } from "iztro";
import { Lunar, LunarYear } from "lunar-typescript";
import { z } from "zod";

const SERVER_NAME = "iztro-openai-mcp";
const SERVER_VERSION = "1.0.0";
const PORT = Number(process.env.PORT || 3000);
const MCP_ENDPOINT = process.env.MCP_ENDPOINT || "/mcp";
const HEALTH_PATH = process.env.HEALTH_PATH || "/health";

const FIVE_ELEMENTS_CLASS = {
  "水二局": 1,
  "木三局": 2,
  "金四局": 3,
  "土五局": 4,
  "火六局": 5
};

const PALACE_NAMES = [
  "命宫",
  "身宫",
  "兄弟",
  "夫妻",
  "子女",
  "财帛",
  "疾厄",
  "迁移",
  "仆役",
  "官禄",
  "田宅",
  "福德",
  "父母",
  "来因",
  "soul",
  "body",
  "siblings",
  "spouse",
  "children",
  "wealth",
  "health",
  "surface",
  "friends",
  "career",
  "property",
  "spirit",
  "parents",
  "origin"
];

const server = new FastMCP({
  name: SERVER_NAME,
  version: SERVER_VERSION,
  health: {
    enabled: true,
    message: "ok",
    path: HEALTH_PATH,
    status: 200
  },
  roots: {
    enabled: false
  }
});

const app = server.getApp();

const commonBirthParams = z.object({
  date: z
    .string()
    .regex(/^\d{4}-\d{1,2}-\d{1,2}$/, 'Birth date must use "YYYY-M-D" format')
    .describe('Birth date in Gregorian calendar format, for example "2000-8-16"'),
  hour: z
    .number()
    .int()
    .min(0)
    .max(23)
    .describe("Birth hour in 24-hour format from 0 to 23"),
  gender: z
    .enum(["male", "female"])
    .describe('Birth gender accepted by iztro: "male" or "female"'),
  fixLeap: z
    .boolean()
    .optional()
    .default(true)
    .describe("Whether to normalize leap month handling"),
  locale: z
    .enum(["zh-CN", "en-US"])
    .optional()
    .default("zh-CN")
    .describe('Response language: "zh-CN" or "en-US"')
});

function getCircularReplacer() {
  const seen = new WeakSet();
  return function replacer(_key, value) {
    if (typeof value === "object" && value !== null) {
      if (seen.has(value)) {
        return undefined;
      }
      seen.add(value);
    }
    return value;
  };
}

function jsonContent(value, replacer = null) {
  return {
    content: [
      {
        type: "text",
        text: JSON.stringify(value, replacer, 2)
      }
    ]
  };
}

function errorContent(message, error) {
  return jsonContent({
    success: false,
    message,
    error: error instanceof Error ? error.message : String(error)
  });
}

function hourToTimeIndex(hour) {
  if (!Number.isInteger(hour) || hour < 0 || hour > 23) {
    throw new Error("Hour must be an integer between 0 and 23");
  }

  if (hour < 1) return 0;
  if (hour < 3) return 1;
  if (hour < 5) return 2;
  if (hour < 7) return 3;
  if (hour < 9) return 4;
  if (hour < 11) return 5;
  if (hour < 13) return 6;
  if (hour < 15) return 7;
  if (hour < 17) return 8;
  if (hour < 19) return 9;
  if (hour < 21) return 10;
  if (hour < 23) return 11;
  return 12;
}

function getAstroYearData({ solarBirthDate, timeIndex, gender, fixLeap, locale }) {
  const astrolabe = astro.bySolar(
    solarBirthDate,
    timeIndex,
    gender,
    fixLeap,
    locale
  );

  const fortunateStartYear =
    astrolabe.rawDates.lunarDate.lunarYear +
    FIVE_ELEMENTS_CLASS[astrolabe.fiveElementsClass];
  const fortunateStartMonth = astrolabe.solarDate.split("-")[1];
  const fortunateStartDay = astrolabe.solarDate.split("-")[2];
  const endYear = fortunateStartYear + 100;

  const decadePeriods = [];
  const agePeriods = [];
  const yearPeriods = [];

  for (let year = fortunateStartYear; year <= endYear; year += 1) {
    const currentDate = [year, fortunateStartMonth, fortunateStartDay].join("-");
    const horoscope = astrolabe.horoscope(currentDate);
    const { stars: _yearStars, yearlyDecStar: _yearDecStar, ...yearly } = horoscope.yearly;

    yearPeriods.push({
      solarDate: horoscope.solarDate,
      yearly
    });

    agePeriods.push({
      solarDate: horoscope.solarDate,
      age: horoscope.age
    });

    const lastDecade = decadePeriods[decadePeriods.length - 1];
    if (!lastDecade || horoscope.decadal.index !== lastDecade.index) {
      const { stars: _decadalStars, ...decadal } = horoscope.decadal;
      decadePeriods.push(decadal);
    }
  }

  return {
    astrolabe,
    decadePeriods,
    agePeriods,
    yearPeriods
  };
}

function getAstroMonthData({ year, fixLeap, locale }) {
  const astrolabe = astro.bySolar(`${year}-01-01`, 1, "male", fixLeap, locale);
  const monthPeriods = [];
  const lunarYear = LunarYear.fromYear(year);
  const months = lunarYear.getMonths();

  for (let i = 0; i < months.length; i += 1) {
    const curLunar = Lunar.fromYmd(months[i].getYear(), months[i].getMonth(), 1);
    const lunarDate = curLunar.toString();
    const solarDate = curLunar.getSolar().toString();
    const horoscope = astrolabe.horoscope(solarDate);
    const { stars: _monthlyStars, ...monthly } = horoscope.monthly;

    monthPeriods.push({
      solarDate,
      lunarDate,
      monthly
    });
  }

  return monthPeriods;
}

function getMutagedPlaces({ date, hour, gender, palaceName, fixLeap, locale }) {
  const timeIndex = hourToTimeIndex(hour);
  const astrolabe = astro.bySolar(date, timeIndex, gender, fixLeap, locale);
  const palace = astrolabe.palace(palaceName);

  if (!palace) {
    throw new Error(`Palace "${palaceName}" was not found`);
  }

  return palace.mutagedPlaces().map((place, index) => ({
    transformation: ["禄", "权", "科", "忌"][index],
    transformationIndex: index,
    place: place
      ? {
          index: place.index,
          name: place.name,
          isBodyPalace: place.isBodyPalace,
          isOriginalPalace: place.isOriginalPalace,
          heavenlyStem: place.heavenlyStem,
          earthlyBranch: place.earthlyBranch,
          majorStars: (place.majorStars || []).map((star) => ({
            name: star.name,
            type: star.type,
            scope: star.scope,
            brightness: star.brightness,
            mutagen: star.mutagen
          }))
        }
      : null
  }));
}

app.get("/", async (c) => {
  return c.json({
    ok: true,
    name: SERVER_NAME,
    version: SERVER_VERSION,
    transport: {
      streamableHttp: MCP_ENDPOINT,
      sse: "/sse",
      health: HEALTH_PATH
    },
    auth: "none",
    tools: [
      "get_astrolabe",
      "get_horoscope_decades",
      "get_horoscope_ages",
      "get_horoscope_years",
      "get_horoscope_months",
      "get_mutaged_places"
    ]
  });
});

server.addTool({
  name: "get_astrolabe",
  description:
    "Generate a Zi Wei Dou Shu birth chart from Gregorian birth date, birth hour, gender, and locale.",
  annotations: {
    title: "Get Astrolabe",
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true
  },
  parameters: commonBirthParams,
  execute: async (args) => {
    try {
      const timeIndex = hourToTimeIndex(args.hour);
      const astrolabe = astro.bySolar(
        args.date,
        timeIndex,
        args.gender,
        args.fixLeap,
        args.locale
      );

      return jsonContent(
        {
          success: true,
          message: "Astrolabe generated successfully",
          data: {
            astrolabe,
            metadata: {
              birthDate: args.date,
              birthHour: args.hour,
              timeIndex,
              gender: args.gender,
              fixLeap: args.fixLeap,
              locale: args.locale,
              generatedAt: new Date().toISOString()
            }
          }
        },
        getCircularReplacer()
      );
    } catch (error) {
      return errorContent("Failed to generate astrolabe", error);
    }
  }
});

server.addTool({
  name: "get_horoscope_decades",
  description:
    "Calculate 10-year Zi Wei Dou Shu luck cycles across the person's life.",
  annotations: {
    title: "Get Horoscope Decades",
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true
  },
  parameters: commonBirthParams,
  execute: async (args) => {
    try {
      const timeIndex = hourToTimeIndex(args.hour);
      const result = getAstroYearData({
        solarBirthDate: args.date,
        timeIndex,
        gender: args.gender,
        fixLeap: args.fixLeap,
        locale: args.locale
      });

      return jsonContent(result.decadePeriods);
    } catch (error) {
      return errorContent("Failed to retrieve decadal periods", error);
    }
  }
});

server.addTool({
  name: "get_horoscope_ages",
  description:
    "Calculate age-based Zi Wei Dou Shu luck periods across the person's life.",
  annotations: {
    title: "Get Horoscope Ages",
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true
  },
  parameters: commonBirthParams,
  execute: async (args) => {
    try {
      const timeIndex = hourToTimeIndex(args.hour);
      const result = getAstroYearData({
        solarBirthDate: args.date,
        timeIndex,
        gender: args.gender,
        fixLeap: args.fixLeap,
        locale: args.locale
      });

      return jsonContent(result.agePeriods);
    } catch (error) {
      return errorContent("Failed to retrieve age periods", error);
    }
  }
});

server.addTool({
  name: "get_horoscope_years",
  description:
    "Calculate yearly Zi Wei Dou Shu horoscope periods across the person's life.",
  annotations: {
    title: "Get Horoscope Years",
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true
  },
  parameters: commonBirthParams,
  execute: async (args) => {
    try {
      const timeIndex = hourToTimeIndex(args.hour);
      const result = getAstroYearData({
        solarBirthDate: args.date,
        timeIndex,
        gender: args.gender,
        fixLeap: args.fixLeap,
        locale: args.locale
      });

      return jsonContent(result.yearPeriods);
    } catch (error) {
      return errorContent("Failed to retrieve yearly periods", error);
    }
  }
});

server.addTool({
  name: "get_horoscope_months",
  description:
    "Calculate all Zi Wei Dou Shu monthly periods for a given Gregorian year.",
  annotations: {
    title: "Get Horoscope Months",
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true
  },
  parameters: z.object({
    year: z
      .number()
      .int()
      .min(1900)
      .max(2100)
      .describe("Gregorian year to inspect, for example 2026"),
    fixLeap: z
      .boolean()
      .optional()
      .default(true)
      .describe("Whether to normalize leap month handling"),
    locale: z
      .enum(["zh-CN", "en-US"])
      .optional()
      .default("zh-CN")
      .describe('Response language: "zh-CN" or "en-US"')
  }),
  execute: async (args) => {
    try {
      return jsonContent(
        getAstroMonthData({
          year: args.year,
          fixLeap: args.fixLeap,
          locale: args.locale
        })
      );
    } catch (error) {
      return errorContent("Failed to retrieve monthly periods", error);
    }
  }
});

server.addTool({
  name: "get_mutaged_places",
  description:
    "Find the four transformed palaces affected by a selected palace in a Zi Wei Dou Shu chart.",
  annotations: {
    title: "Get Mutaged Places",
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true
  },
  parameters: commonBirthParams.extend({
    palaceName: z
      .union([
        z
          .number()
          .int()
          .min(0)
          .max(11)
          .describe("Palace index from 0 to 11"),
        z.enum(PALACE_NAMES)
      ])
      .describe(
        'Palace index or palace name in Chinese/English, for example 0, "命宫", or "career"'
      )
  }),
  execute: async (args) => {
    try {
      return jsonContent({
        success: true,
        message: `Mutaged places for ${args.palaceName} retrieved successfully`,
        data: {
          sourcePalace: args.palaceName,
          mutagedPlaces: getMutagedPlaces(args),
          metadata: {
            birthDate: args.date,
            birthHour: args.hour,
            gender: args.gender,
            fixLeap: args.fixLeap,
            locale: args.locale,
            generatedAt: new Date().toISOString()
          }
        }
      });
    } catch (error) {
      return errorContent("Failed to get mutaged places", error);
    }
  }
});

async function main() {
  await server.start({
    transportType: "httpStream",
    httpStream: {
      host: "0.0.0.0",
      port: PORT,
      endpoint: MCP_ENDPOINT,
      stateless: true
    }
  });

  console.log(
    `${SERVER_NAME}@${SERVER_VERSION} listening on port ${PORT} with MCP at ${MCP_ENDPOINT} and SSE at /sse`
  );
}

process.on("SIGINT", () => process.exit(0));
process.on("SIGTERM", () => process.exit(0));

main().catch((error) => {
  console.error("Failed to start MCP server:", error);
  process.exit(1);
});
