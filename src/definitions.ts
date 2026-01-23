export interface HttpLocalServerSwifterPlugin {
  echo(options: { value: string }): Promise<{ value: string }>;
}
