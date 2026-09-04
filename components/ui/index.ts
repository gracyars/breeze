/**
 * Primitivos do design system do Breeze (F0).
 * Regras e contraste medido: docs/design-system.md
 * Regras de gráfico: docs/design/graficos.md
 */
export { Button, type ButtonProps } from "./button";
export { Input, CampoTexto, type InputProps, type CampoTextoProps } from "./input";
export {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
  CardFooter,
} from "./card";
export { Badge, BadgeStatus, type BadgeProps, type BadgeStatusProps } from "./badge";
export {
  Table,
  TableCaption,
  TableHeader,
  TableBody,
  TableFooter,
  TableRow,
  TableHead,
  TableCell,
} from "./table";
export {
  Destaque,
  TrechoFonte,
  RespostaSintetizada,
  SeloProveniencia,
  type TrechoFonteProps,
  type RespostaSintetizadaProps,
  type SeloProvenienciaProps,
} from "./citacao";
export {
  GraficoBarras,
  GraficoOrcadoRealizado,
  type ItemBarra,
  type ItemOrcado,
} from "./barras";
export { Slot } from "./slot";
